package Ham::RTTY::Generator;
use 5.020;
use strict;
use warnings;
use Ham::RTTY::Events              qw(validate_events to_samples);
use Ham::RTTY::_Internal::Validate qw(fail number integer options named_arguments);
use Ham::RTTY::_Internal::Backend;
our $VERSION = '0.001';
my $PI = 4 * atan2(1, 1);

sub new {
    my ($class, @pairs) = @_;
    my $self = bless $class->validate(@pairs), $class;
    return $self->reset;
}

sub validate {
    my ($class, @pairs) = @_;
    my %args = named_arguments(@pairs);
    my $args = \%args;
    options($args, qw(sample_rate frequency amplitude attack_ms release_ms max_samples backend));
    my $rate = integer('sample_rate', $args->{sample_rate} // 16000, 1000, 384000);
    return {
        sample_rate => $rate,
        backend     => Ham::RTTY::_Internal::Backend::resolve($args->{backend}),
        frequency   => number(
            'frequency', $args->{frequency} // ($rate / 2 - 1 >= 700 ? 700 : $rate / 4),
            1,           $rate / 2 - 1
        ),
        amplitude   => number('amplitude',  $args->{amplitude}  // 0.8, 0, 1),
        attack_ms   => number('attack_ms',  $args->{attack_ms}  // 5,   0, 1000),
        release_ms  => number('release_ms', $args->{release_ms} // 5,   0, 1000),
        max_samples => integer('max_samples', $args->{max_samples} // 10000000, 1, 100000000),
    };
}

sub reset {    ## no critic (Subroutines::ProhibitBuiltinHomonyms)
    my ($s) = @_;
    $s->{state}    = 'READY';
    $s->{produced} = 0;
    return $s;
}
sub state { my ($self) = @_; return $self->{state} }    ## no critic (Subroutines::ProhibitBuiltinHomonyms)

sub _segments {
    my ($self, $events) = @_;
    my $field   = validate_events($events);
    my $sampled = $field eq 'duration' ? to_samples($events, $self->{sample_rate}) : $events;
    fail('RTTY_E_ARGUMENT', 'Sample rate mismatch')
        unless $sampled->{sample_rate} == $self->{sample_rate};
    my @segments = map { +{%{$_}} } @{$sampled->{segments}};
    my $total    = 0;
    $total += $_->{samples} for @segments;
    fail('RTTY_E_RESOURCE',
        'Generation exceeds max_samples; increase max_samples or generate a shorter message')
        if $total > $self->{max_samples};
    return \@segments;
}

sub stream {
    my ($self, $events, $block_size) = @_;
    integer('block_size', $block_size //= 4096, 1, 1000000);
    fail('RTTY_E_STATE', 'Reset generator before starting another stream')
        unless $self->{state} eq 'READY';
    my @segments = @{$self->_segments($events)};
    my ($si, $offset, $absolute) = (0, 0, 0);
    $self->{state} = 'ACTIVE';
    my $generation = ++$self->{generation};
    return $self->_pdl_stream(\@segments, $block_size, $generation)
        if $self->{backend} eq 'pdl';
    return sub {
        fail('RTTY_E_STATE', 'Generator stream was reset or replaced')
            if $generation != ($self->{generation} // 0) || $self->{state} eq 'READY';
        if ($si > $#segments) { $self->{state} = 'FINISHED'; return }
        my @out;
        while (@out < $block_size && $si <= $#segments) {
            my $seg = $segments[$si];
            if ($seg->{state} eq 'off') {
                my $count = $seg->{samples} - $offset;
                $count = $block_size - @out if $count > $block_size - @out;
                push @out, (0) x $count;
                $absolute += $count;
                $offset   += $count;
                if ($offset == $seg->{samples}) { ++$si; $offset = 0 }
                next;
            }
            my $value = 0;
            if ($seg->{state} eq 'on') {
                my $attack  = $self->{attack_ms} * $self->{sample_rate} / 1000;
                my $release = $self->{release_ms} * $self->{sample_rate} / 1000;
                $attack  = $seg->{samples} / 2 if $attack > $seg->{samples} / 2;
                $release = $seg->{samples} / 2 if $release > $seg->{samples} / 2;
                my $gain = 1;
                $gain *= 0.5 * (1 - cos($PI * $offset / $attack)) if $attack && $offset < $attack;
                my $remaining_mark = $seg->{samples} - 1 - $offset;
                $gain *= 0.5 * (1 - cos($PI * $remaining_mark / $release))
                    if $release && $remaining_mark < $release;
                my $cycles = $absolute * $self->{frequency} / $self->{sample_rate};
                my $phase  = 2 * $PI * ($cycles - int($cycles));
                $value = $self->{amplitude} * $gain * sin($phase);
            }
            push @out, $value;
            ++$absolute;
            if (++$offset == $seg->{samples}) { ++$si; $offset = 0 }
        }
        $self->{produced} = $absolute;
        $self->{state}    = 'FINISHED' if $si > $#segments;
        return \@out;
    };
}

sub _pdl_stream {
    my ($self, $segments, $block_size, $generation) = @_;
    my ($si, $offset, $absolute) = (0, 0, 0);
    return sub {
        fail('RTTY_E_STATE', 'Generator stream was reset or replaced')
            if $generation != ($self->{generation} // 0) || $self->{state} eq 'READY';
        if ($si > $#{$segments}) { $self->{state} = 'FINISHED'; return }
        my @out;
        while (@out < $block_size && $si <= $#{$segments}) {
            my $seg   = $segments->[$si];
            my $count = $seg->{samples} - $offset;
            $count = $block_size - @out if $count > $block_size - @out;
            push @out, @{Ham::RTTY::_Internal::PDL::tone($self, $seg, $offset, $absolute, $count)};
            $absolute += $count;
            $offset   += $count;
            if ($offset == $seg->{samples}) { ++$si; $offset = 0 }
        }
        $self->{produced} = $absolute;
        $self->{state}    = 'FINISHED' if $si > $#{$segments};
        return \@out;
    };
}

sub generate {
    my ($self, $events) = @_;
    my $next = $self->stream($events);
    my @out;
    while (my $block = $next->()) { push @out, @{$block} }
    return \@out;
}

sub result {
    my ($self) = @_;
    return {
        state       => $self->{state},
        samples     => $self->{produced},
        sample_rate => $self->{sample_rate}
    };
}
1;

=encoding UTF-8

=head1 NAME

Ham::RTTY::Generator - synthesize keyed mono tones from events

=head1 SYNOPSIS

    use strict;
    use warnings;
    use Ham::RTTY::Encoder;
    use Ham::RTTY::Generator;

    my $events = Ham::RTTY::Encoder->new(wpm => 20)->events('SOS');
    my $generator = Ham::RTTY::Generator->new(
        sample_rate => 8000, frequency => 650);
    my $samples = $generator->generate($events);
    print scalar(@{$samples}), " samples\n";

=head1 DESCRIPTION

Produces normalized mono Perl sample arrays from timed or sampled ON/OFF
events. It does not play audio or write WAV headers. Use L<Ham::RTTY::Audio>
for PCM files or L<Ham::RTTY/samples> to start with text.

=head1 METHODS

=head2 new

    my $generator = Ham::RTTY::Generator->new(%options);

Returns a generator in C<READY> state. Options and inclusive ranges:

=over 4

=item * C<sample_rate>: 16000 Hz; integer 1000..384000.

=item * C<frequency>: 700 Hz when valid, otherwise C<sample_rate / 4>. Valid range is 1..C<sample_rate / 2 - 1> Hz.

=item * C<amplitude>: 0.8; finite number 0..1.

=item * C<attack_ms>, C<release_ms>: 5 each; finite number 0..1000 milliseconds.

=item * C<max_samples>: 10000000; integer 1..100000000.

=item * C<backend>: C<perl> (default), C<pdl> or C<auto>. See L<Ham::RTTY/OPTIONAL PDL BACKEND>.

=back

Optional undefined values use defaults. Invalid, duplicate or unknown options
raise C<RTTY_E_ARGUMENT>. Speed is determined by input events, not generator
options; C<wpm> is an Encoder option.

=head2 validate

    my $configuration = Ham::RTTY::Generator->validate(%options);

Validates the same options as C<new> and returns a fresh normalized
configuration hash without constructing an instance. Unknown names, duplicate
options and invalid values raise the same errors as C<new>. Defaults are
resolved in the returned hash, including the selected backend. Optional PDL
loading/availability checks still occur. No stream is started or audio produced.

=head2 stream

    my $next = $generator->stream($events, $block_size);
    while (my $block = $next->()) {
        # Consume the normalized samples in this array reference.
    }

Requires C<READY>. Validates and copies the complete event sequence before
returning an iterator. TimedEvents are converted to samples; SampledEvents
must match the configured rate. C<block_size> defaults to 4096 and is an
integer in 1..1000000. The iterator returns arrays of at most that length,
then C<undef> at EOF; the final block may be shorter. Empty events produce
immediate EOF. The whole-message sample ceiling includes silence and is
checked before output. Streaming bounds sample-buffer size, not event history.

The generator becomes C<ACTIVE> when the stream starts and C<FINISHED> when
it is exhausted. Consume the stream before starting another generation.

=head2 generate

    my $samples = $generator->generate($events);

Collects C<stream> into one sample array and returns it. Subject to the same
validation, READY-state requirement and total sample limit. Collected Perl
arrays can require substantially more memory than packed PCM.

=head2 result

    my $progress = $generator->result;

Returns a fresh hash with C<state>, C<samples> (number produced so far) and
C<sample_rate>. It contains progress, not generated sample values.

=head2 state

    my $state = $generator->state;

Returns C<READY>, C<ACTIVE> or C<FINISHED>.

=head2 reset

    $generator->reset;

Discards progress, preserves configuration, returns the object and restores
C<READY>. All existing iterators become invalid; calling them raises
C<RTTY_E_STATE>. Previously returned sample arrays remain usable.

=head1 WAVEFORM

ON runs use a sine wave; OFF runs are zero. Amplitude is a fraction of full
scale, with 0 producing silence. Attack is the fade-in at a mark start; release
is the fade-out at its end. Phase is based on the absolute
sample index and advances through silence. Raised-cosine attack/release
ramps lie inside each mark and are independently shortened to at most half
the mark length. They add no extra samples.

Within one backend and configuration, changing block boundaries does not
change sample values. Optional PDL calculations can differ slightly from
the Perl backend; see L<Ham::RTTY/OPTIONAL PDL BACKEND>.

=head1 ERRORS

Invalid options, samples/rate mismatch or arguments raise C<RTTY_E_ARGUMENT>.
Invalid event timing/resolution raises C<RTTY_E_TIMING>; excessive events or
sample counts raise C<RTTY_E_RESOURCE>. Reuse without reset and invalidated
iterators raise C<RTTY_E_STATE>. Validation errors preserve generator state.

=head1 AUTHOR

Giacomo Picchiarelli

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2026 Giacomo Picchiarelli.
Artistic License 2.0. See F<LICENSE> in the source distribution.

=cut
