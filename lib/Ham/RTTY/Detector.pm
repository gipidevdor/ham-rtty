package Ham::RTTY::Detector;
use 5.020;
use strict;
use warnings;
use Ham::RTTY::Generator;
use Ham::RTTY::Decoder;
use Ham::RTTY::Result;
use Ham::RTTY::_Internal::Validate qw(fail number integer options samples named_arguments);
our $VERSION = '0.001';
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
    my $baud        = number('baud', $args{baud} // 45.45, 20, 300);
    my $default_max = 3000 - $gen{shift};
    my $nyquist_max = $gen{sample_rate} / 2 - $gen{shift} - 0.000001;
    $default_max = $nyquist_max if $nyquist_max < $default_max;
    my $min = number('min_frequency', $args{min_frequency} // 300, 300, 3000 - $gen{shift});
    my $max =
        number('max_frequency', $args{max_frequency} // $default_max, $min, 3000 - $gen{shift});
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
    delete @{$self}{qw(final snapshot)};
    return $self;
}
sub state { my ($self) = @_; return $self->{state} }    ## no critic (Subroutines::ProhibitBuiltinHomonyms)

sub _powers {
    my ($self, $values, $frequencies) = @_;
    if ($self->{backend} eq 'pdl') {
        return Ham::RTTY::_Internal::PDL::powers($values, $frequencies, $self->{sample_rate})
            if @{$values} * @{$frequencies} <= 65536;

        # Bound transient projection matrices even for wide, high-rate searches.
        my $width = int(65536 / @{$values}) || 1;
        my @projected;
        for (my $offset = 0; $offset < @{$frequencies}; $offset += $width) {
            my $end = $offset + $width - 1;
            $end = $#{$frequencies} if $end > $#{$frequencies};
            push @projected,
                @{
                Ham::RTTY::_Internal::PDL::powers($values, [@{$frequencies}[$offset .. $end]],
                    $self->{sample_rate})
                };
        }
        return \@projected;
    }
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
    my ($self, $values, $offset) = @_;
    $offset //= 0;
    return $self->_consume($values) if !$offset && @{$values} <= 4096;
    for (; $offset < @{$values}; $offset += 4096) {
        my $end = $offset + 4095;
        $end = $#{$values} if $end > $#{$values};
        $self->_consume([@{$values}[$offset .. $end]]);
    }
    return;
}

sub _consume {
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

sub _preflight {
    my ($self, $new_total) = @_;
    fail('RTTY_E_RESOURCE', 'Reception exceeds max_frames')
        if int($new_total / $self->{hop}) + 1 > $self->{max_frames};

    # Each feature can introduce at most one run. Preflight before mutation.
    fail('RTTY_E_RESOURCE', 'Reception exceeds max_segments')
        if int($new_total / $self->{hop}) + 1 > $self->{max_segments};
    return;
}

sub feed {
    my ($self, $values) = @_;
    fail('RTTY_E_STATE', 'Detector is finalized') if $self->{state} eq 'FINISHED';
    samples($values, 1000000);
    my $new_total = $self->{total} + @{$values};
    $self->_preflight($new_total);
    my $consumed = 0;
    if (!$self->{acquired}) {
        my $target = int($self->{sample_rate} * 0.5);
        my $needed = $target - @{$self->{acquisition}};
        $consumed = @{$values} < $needed ? scalar @{$values} : $needed;
        push @{$self->{acquisition}}, @{$values}[0 .. $consumed - 1] if $consumed;
        $self->_acquire if @{$self->{acquisition}} >= $target;
    }
    $self->_process($values, $consumed) if $self->{acquired};
    $self->{total} = $new_total;
    delete $self->{snapshot};
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
sub result { my ($self) = @_; return $self->{final} // ($self->{snapshot} //= $self->_snapshot(0)) }

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

=head1 DESCRIPTION

Receives normalized mono samples in successive blocks. Two narrowband energy
measurements produce MARK/SPACE decisions, which are passed to the start-stop
decoder. Supply the recording's sample rate and baud rate.

Audio reception is experimental. Check the Result warnings before using
received text. WAV helpers read the sample rate from the file header.

=head1 METHODS

=head2 new

    my $detector = Ham::RTTY::Detector->new(%options);

Returns a detector in C<READY> state. Named options:

=over 4

=item * C<sample_rate>, C<mark>, C<shift>, C<reverse>, C<backend>

Use the defaults and ranges in L<Ham::RTTY::Generator/new>. These are the only
Generator options accepted by Detector.

=item * C<baud>

45.45 by default; finite number 20..300. Set this to the sender's rate. There
is no automatic baud mode.

=item * C<variant>, C<usos>

Use the defaults and ranges in L<Ham::RTTY::Decoder/new>.

=item * C<atc>

1 by default; integer 0 or 1. Enables automatic threshold correction using the
tracked tone peaks.

=item * C<search>

0 by default; integer 0 or 1. When enabled, acquire a tone pair at the
configured shift from the first half second of input.

=item * C<min_frequency>, C<max_frequency>

Search bounds for the lower tone, in Hz. Defaults are 300 and C<3000 - shift>.
The minimum is at least 300; the maximum is at least the minimum and at most
C<3000 - shift>, reduced when necessary so SPACE stays at least one
microhertz below Nyquist. Both tones must be below Nyquist. The bounds are validated
even when search is off.

=item * C<frequency_step>

10 Hz by default; finite number 1..500. The search band may contain at most
512 candidate pairs.

=item * C<max_frames>

200000 by default; integer 1..1000000.

=item * C<max_segments>

100000 by default; integer 1..1000000. Both history limits conservatively
bound accepted hop count before a feed changes receiver state.

=back

Undefined optional values use defaults. Invalid, duplicate and unknown
options raise C<RTTY_E_ARGUMENT>.
A search band exceeding 512 pairs raises C<RTTY_E_RESOURCE>.

=head2 feed

    $detector->feed($samples);

Accepts arrays of finite normalized mono values in [-1,1], at most 1000000 per
call. Validation and conservative feature limits precede mutation. Feed after
finish raises C<RTTY_E_STATE>. Windows span approximately 0.65 bit, advancing
about 1/12 bit. Fixed tone powers use Goertzel in Perl or a broadcast two-tone
projection in PDL. ATC normalizes independently decaying tone peaks with a
shared floor. Optional search acquires once from the first half second;
acquisition retains only the first half second, independently of incoming
block boundaries. No full raw-audio history is retained.

Incoming arrays are processed in pieces of at most 4096 samples; the filter
buffer additionally holds its decision window. The PDL path batches wide
searches to bound each transient projection matrix to 65,536 cells under the
supported rate/baud ranges. Samples are neither dropped nor resampled by
these memory bounds.

=head2 result

    my $result = $detector->result;

Returns a cumulative provisional Result without flushing partial audio. It
runs the UART synchroniser over bounded retained decisions. Diagnostics
include C<measured_bit_period> in seconds (median observed one-bit runs, undef
without evidence), C<mark_space_level_ratio>, C<framing_error_count> and
C<analyzed_samples>. Configured timing is reported separately from measured
timing.

=head2 finish

    my $result = $detector->finish;

Processes a short pending acquisition once and returns a cached complete
Result. A partial analysis window remains unprocessed at EOF. Silence reports
C<RTTY_W_NO_SIGNAL>. Reception warnings must be inspected; completion is not
an accuracy claim.

=head2 reset

    $detector->reset;

Discards audio/feature history and snapshots, preserves configuration and
restores READY. Returns the receiver.

=head2 state

    my $state = $detector->state;

Returns READY, ACTIVE or FINISHED.

=head1 LIMITS

No simultaneous stations, automatic baud/shift identification, equalisation or
diversity. Synthetic performance does not establish off-air accuracy.

=head1 AUTHOR

Giacomo Picchiarelli

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2026 Giacomo Picchiarelli.
Artistic License 2.0. See F<LICENSE> in the source distribution.

=cut
