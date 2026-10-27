package Ham::RTTY::Detector;
use 5.020;
use strict;
use warnings;
use Ham::RTTY::Generator;
use Ham::RTTY::Decoder;
use Ham::RTTY::Result;
use Ham::RTTY::_Internal::Validate qw(fail number integer options samples named_arguments);
our $VERSION = '0.01';
my $PI = 4 * atan2(1, 1);

sub new {
    my ($class, @pairs) = @_;
    my %args = named_arguments(@pairs);
    options(\%args,
        qw(sample_rate baud mark shift reverse variant usos atc search min_frequency max_frequency frequency_step max_frames max_segments backend)
    );
    my %gen = %{Ham::RTTY::Generator->validate(
            map { exists($args{$_}) ? ($_ => $args{$_}) : () }
                qw(sample_rate mark shift reverse backend)
        )
    };
    my $baud = number('baud',          $args{baud}          // 45.45, 20,  300);
    my $min  = number('min_frequency', $args{min_frequency} // 300,   300, 3000 - $gen{shift});
    my $max  = number('max_frequency', $args{max_frequency} // 3000 - $gen{shift},
        $min, 3000 - $gen{shift});
    fail('RTTY_E_ARGUMENT', 'Search tones must be below Nyquist')
        if $max + $gen{shift} >= $gen{sample_rate} / 2;
    my $step = number('frequency_step', $args{frequency_step} // 10, 1, 500);
    fail('RTTY_E_RESOURCE', 'Search exceeds 512 candidate pairs') if ($max - $min) / $step > 511;
    my $self = bless {
        %gen,
        baud           => $baud,
        variant        => $args{variant} // 'ita2',
        usos           => $args{usos}    // 1,
        atc            => integer('atc',    $args{atc}    // 1, 0, 1),
        search         => integer('search', $args{search} // 0, 0, 1),
        min_frequency  => $min,
        max_frequency  => $max,
        frequency_step => $step,
        max_frames     => integer('max_frames',   $args{max_frames}   // 200000, 1, 1000000),
        max_segments   => integer('max_segments', $args{max_segments} // 100000, 1, 1000000)
    }, $class;
    Ham::RTTY::Decoder->new(variant => $self->{variant}, usos => $self->{usos}, baud => $baud);
    $self->{window_size} = int($self->{sample_rate} / $baud * 0.65 + 0.5);
    $self->{hop}         = int($self->{sample_rate} / $baud / 12 + 0.5) || 1;
    return $self->reset;
}

sub reset {    ## no critic (Subroutines::ProhibitBuiltinHomonyms)
    my ($self) = @_;
    @{$self}{qw(state total frames mark_power space_power)} = ('READY', 0, 0, 0, 0);
    $self->{buffer}      = [];
    $self->{segments}    = [];
    $self->{peaks}       = [1e-12, 1e-12];
    $self->{acquisition} = [];
    $self->{acquired}    = !$self->{search};
    delete $self->{final};
    return $self;
}
sub state { my ($self) = @_; return $self->{state} }    ## no critic (Subroutines::ProhibitBuiltinHomonyms)

sub _powers {
    my ($self, $values, $frequencies) = @_;
    return Ham::RTTY::_Internal::PDL::powers($values, $frequencies, $self->{sample_rate})
        if $self->{backend} eq 'pdl';
    my @powers;
    for my $frequency (@{$frequencies}) {
        my $coefficient = 2 * cos(2 * $PI * $frequency / $self->{sample_rate});
        my ($q1, $q2) = (0, 0);
        for my $value (@{$values}) {
            my $q0 = $value + $coefficient * $q1 - $q2;
            $q2 = $q1;
            $q1 = $q0;
        }
        push @powers, $q1 * $q1 + $q2 * $q2 - $coefficient * $q1 * $q2;
    }
    return \@powers;
}

sub _acquire {
    my ($self) = @_;
    my (@frequencies, @scores);
    for (
        my $f = $self->{min_frequency};
        $f <= $self->{max_frequency};
        $f += $self->{frequency_step}
        )
    {
        push @frequencies, $f, $f + $self->{shift};
    }
    @scores = (0) x @frequencies;
    my $n = $self->{window_size};
    for (my $offset = 0; $offset + $n <= @{$self->{acquisition}}; $offset += $n) {
        my $powers =
            $self->_powers([@{$self->{acquisition}}[$offset .. $offset + $n - 1]], \@frequencies);
        $scores[$_] += $powers->[$_] for 0 .. $#scores;
    }
    my ($best, $score) = (0, -1);
    for (my $i = 0; $i < @scores; $i += 2) {
        my $candidate = sqrt($scores[$i] * $scores[$i + 1]);
        if ($candidate > $score) { ($best, $score) = ($i, $candidate) }
    }
    $self->{mark}     = $frequencies[$best];
    $self->{acquired} = 1;
    my $values = $self->{acquisition};
    $self->{acquisition} = [];
    $self->_process($values);
    return;
}

sub _process {
    my ($self, $values) = @_;
    push @{$self->{buffer}}, @{$values};
    my $n           = $self->{window_size};
    my @frequencies = ($self->{mark}, $self->{mark} + $self->{shift});
    @frequencies = reverse @frequencies if $self->{reverse};
    while (@{$self->{buffer}} >= $n) {
        my $powers   = $self->_powers([@{$self->{buffer}}[0 .. $n - 1]], \@frequencies);
        my @adjusted = @{$powers};
        my $peak     = $powers->[0] > $powers->[1] ? $powers->[0] : $powers->[1];
        for my $i (0, 1) {
            $self->{peaks}[$i] *= 0.999;
            $self->{peaks}[$i] = $powers->[$i] if $powers->[$i] > $self->{peaks}[$i];
            $adjusted[$i] /= ($self->{peaks}[$i] > $peak * 0.1 ? $self->{peaks}[$i] : $peak * 0.1)
                if $self->{atc} && $peak > 1e-20;
        }
        $self->{mark_power}  += $powers->[0];
        $self->{space_power} += $powers->[1];
        my $state    = $adjusted[0] >= $adjusted[1] ? 'mark' : 'space';
        my $duration = $self->{hop};

        # Features refer to window centres. Preserve the initial half-window.
        $duration += int($n / 2) if !$self->{frames};
        if (@{$self->{segments}} && $self->{segments}[-1]{state} eq $state) {
            $self->{segments}[-1]{samples} += $duration;
        }
        else { push @{$self->{segments}}, {state => $state, samples => $duration} }
        splice @{$self->{buffer}}, 0, $self->{hop};
        ++$self->{frames};
    }
    return;
}

sub feed {
    my ($self, $values) = @_;
    fail('RTTY_E_STATE', 'Detector is finalized') if $self->{state} eq 'FINISHED';
    samples($values, 1000000);
    my $new_total = $self->{total} + @{$values};
    fail('RTTY_E_RESOURCE', 'Reception exceeds max_frames')
        if int($new_total / $self->{hop}) + 1 > $self->{max_frames};

    # Each feature can introduce at most one run. Preflight before mutation.
    fail('RTTY_E_RESOURCE', 'Reception exceeds max_segments')
        if int($new_total / $self->{hop}) + 1 > $self->{max_segments};
    if (!$self->{acquired}) {
        push @{$self->{acquisition}}, @{$values};
        $self->_acquire if @{$self->{acquisition}} >= int($self->{sample_rate} * 0.5);
    }
    else { $self->_process($values) }
    $self->{total} = $new_total;
    $self->{state} = 'ACTIVE';
    return $self;
}

sub _snapshot {
    my ($self, $complete) = @_;
    my $decoder = Ham::RTTY::Decoder->new(
        baud         => $self->{baud},
        variant      => $self->{variant},
        usos         => $self->{usos},
        max_segments => $self->{max_segments}
    );
    $decoder->feed({sample_rate => $self->{sample_rate}, segments => $self->{segments}});
    my $h = ($complete ? $decoder->finish : $decoder->result)->as_hash;
    $h->{frequency} = $self->{mark};
    my $energy = $self->{mark_power} + $self->{space_power};
    if ($energy < 1e-8) {
        $h->{text}     = '';
        $h->{warnings} = [{code => 'RTTY_W_NO_SIGNAL', message => 'No usable tone energy'}];
    }
    my @periods =
        sort { $a <=> $b }
        map  { $_->{samples} / $self->{sample_rate} }
        grep { abs($_->{samples} * $self->{baud} / $self->{sample_rate} - 1) < 0.25 }
        @{$self->{segments}};
    $h->{diagnostics}{measured_bit_period} = @periods ? $periods[int(@periods / 2)] : undef;
    $h->{diagnostics}{mark_space_level_ratio} =
        $self->{space_power} > 0 ? $self->{mark_power} / $self->{space_power} : undef;
    $h->{diagnostics}{analyzed_samples} = $self->{total};
    $h->{diagnostics}{frame_samples}    = $self->{hop};
    return Ham::RTTY::Result->new(%{$h});
}
sub result { my ($self) = @_; return $self->{final} // $self->_snapshot(0) }

sub finish {
    my ($self) = @_;
    return $self->{final} if $self->{state} eq 'FINISHED';
    $self->_acquire       if !$self->{acquired} && @{$self->{acquisition}};
    $self->{final} = $self->_snapshot(1);
    $self->{state} = 'FINISHED';
    return $self->{final};
}
1;

=encoding UTF-8

=head1 NAME

Ham::RTTY::Detector - incremental dual-tone RTTY audio receiver

=head1 SYNOPSIS

    use strict;
    use warnings;
    use Ham::RTTY;
    my $rtty = Ham::RTTY->new;
    my $next = $rtty->stream_samples('CQ');
    my $detector = $rtty->detector(baud => 45.45);
    while (my $block = $next->()) { $detector->feed($block) }
    print $detector->finish->text, "\n";

=head1 METHODS

=head2 new

Ham::RTTY::Detector->new(%options) constructs a READY receiver. Tone/rate/backend/reverse ranges follow L<Ham::RTTY::Generator/new>. C<baud> defaults to 45.45, finite 20..300; explicit known baud is required for reliable reception in 1.0; the default is a configuration, not auto-detection. C<variant> and C<usos> follow L<Ham::RTTY::Decoder/new>. C<atc> defaults to 1; C<search> defaults to 0; both integer 0 or 1. Search min_frequency defaults to 300 Hz, max_frequency to 3000-shift; the band must lie within 300..3000 and below Nyquist. C<frequency_step> defaults to 10 Hz, finite 1..500; at most 512 pairs. C<max_frames> defaults to 200000 and C<max_segments> to 100000, integer 1..1000000. Both conservatively bound accepted hop count before mutation. Unknown/duplicate options raise C<RTTY_E_ARGUMENT>.

=head2 feed

$detector->feed($samples) accepts arrays of finite normalized mono values in [-1,1], at most 1000000 per call. Validation and conservative feature limits precede mutation. Feed after finish raises C<RTTY_E_STATE>. Windows span approximately 0.65 bit, advancing about 1/12 bit. Fixed tone powers use Goertzel in Perl or a broadcast two-tone projection in PDL. ATC normalizes independently decaying tone peaks with a shared floor. Optional search acquires once from the first half second; acquisition buffer is bounded by half a second plus one input block. No full raw-audio history is retained.

=head2 result

$detector->result returns a cumulative provisional Result without flushing partial audio. It runs the UART synchroniser over bounded retained decisions. Diagnostics include measured_bit_period in seconds (median observed one-bit runs, undef without evidence), mark_space_level_ratio, framing_error_count and analyzed_samples. Configured timing is reported separately from measured timing.

=head2 finish

$detector->finish processes a short pending acquisition once and returns a cached complete Result. The incomplete analysis window is not padded with invented samples. Silence reports RTTY_W_NO_SIGNAL. Reception warnings must be inspected; completion is not an accuracy claim.

=head2 reset

$detector->reset discards audio/feature history and snapshots, preserves configuration and restores READY. Returns the receiver.

=head2 state

$detector->state returns READY, ACTIVE or FINISHED.

=head1 LIMITS

No simultaneous stations, automatic baud/shift identification, equalisation or diversity. Synthetic performance does not establish off-air accuracy.

=head1 AUTHOR

Giacomo Picchiarelli

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2026 Giacomo Picchiarelli. Artistic License 2.0. See F<LICENSE>.

=cut
