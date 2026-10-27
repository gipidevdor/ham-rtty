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
    options($args, qw(sample_rate mark shift reverse amplitude max_samples backend));
    my $rate  = integer('sample_rate', $args->{sample_rate} // 16000, 1000, 384000);
    my $mark  = number('mark',  $args->{mark}  // 2125, 300, 3000);
    my $shift = number('shift', $args->{shift} // 170,  1,   2700);
    number('space', $mark + $shift, 300, 3000);
    fail('RTTY_E_ARGUMENT', 'Tones must be below Nyquist') if $mark + $shift >= $rate / 2;
    return {
        sample_rate => $rate,
        mark        => $mark,
        shift       => $shift,
        reverse     => integer('reverse', $args->{reverse}    // 0, 0, 1),
        amplitude   => number('amplitude', $args->{amplitude} // 0.8, 0, 1),
        backend     => Ham::RTTY::_Internal::Backend::resolve($args->{backend}),
        max_samples => integer('max_samples', $args->{max_samples} // 10000000, 1, 100000000)
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
    my ($si, $offset, $absolute, $phase) = (0, 0, 0, 0);
    $self->{state} = 'ACTIVE';
    my $generation = ++$self->{generation};
    return sub {
        fail('RTTY_E_STATE', 'Generator stream was reset or replaced')
            if $generation != ($self->{generation} // 0) || $self->{state} eq 'READY';
        if ($si > $#segments) { $self->{state} = 'FINISHED'; return }
        my @out;
        while (@out < $block_size && $si <= $#segments) {
            my $seg   = $segments[$si];
            my $count = $seg->{samples} - $offset;
            $count = $block_size - @out if $count > $block_size - @out;
            my $high = ($seg->{state} eq 'space') != $self->{reverse};
            my $step =
                2 * $PI * ($self->{mark} + ($high ? $self->{shift} : 0)) / $self->{sample_rate};
            if ($self->{backend} eq 'pdl') {
                push @out,
                    @{Ham::RTTY::_Internal::PDL::fsk_tone($phase, $step, $count, $self->{amplitude})
                    };
                $phase += $step * $count;
                $phase -= 2 * $PI * int($phase / (2 * $PI));
            }
            else {
                for (1 .. $count) {
                    push @out, $self->{amplitude} * sin($phase);
                    $phase += $step;
                    $phase -= 2 * $PI if $phase >= 2 * $PI;
                }
            }
            $absolute += $count;
            $offset   += $count;
            if ($offset == $seg->{samples}) { ++$si; $offset = 0 }
        }
        $self->{produced} = $absolute;
        $self->{state}    = 'FINISHED' if $si > $#segments;
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

Ham::RTTY::Generator - continuous-phase two-tone AFSK synthesis

=head1 SYNOPSIS

    use strict;
    use warnings;
    use Ham::RTTY::Encoder;
    use Ham::RTTY::Generator;
    my $events = Ham::RTTY::Encoder->new->events('CQ');
    my $samples = Ham::RTTY::Generator->new(sample_rate => 8000)->generate($events);
    print scalar(@{$samples}), " samples\n";

=head1 METHODS

=head2 new

Ham::RTTY::Generator->new(%options) returns a READY generator. C<sample_rate> is integer 1000..384000, default 16000; both tones must be strictly below Nyquist. C<mark> defaults to 2125 Hz, range 300..3000; C<shift> defaults to 170 Hz, positive range 1..2700 with mark+shift at most 3000. C<reverse> defaults to 0 (integer 0 or 1). C<amplitude> defaults to 0.8, finite 0..1. C<backend> is perl (default), pdl, or auto (availability only). C<max_samples> defaults to 10000000, integer 1..100000000. Invalid/unknown/duplicate options raise C<RTTY_E_ARGUMENT>.

=head2 validate

Ham::RTTY::Generator->validate(%options) returns a normalized fresh configuration using the same validation as new, including optional backend availability checks.

=head2 stream

$generator->stream($events, $block_size) validates and copies events before returning an iterator of normalized mono sample arrays. Block size defaults to 4096, integer 1..1000000. The iterator returns undef at EOF. Sampled events must match the configured rate. Total output exceeding max_samples raises C<RTTY_E_RESOURCE>. Invalid state or an iterator invalidated by reset raises C<RTTY_E_STATE>. One phase accumulator advances continuously across every mark/space transition. Frequency-transition shaping is not implemented.

=head2 generate

$generator->generate($events) collects stream into one sample array. The same limits and state requirements apply. The array can occupy much more memory than PCM bytes.

=head2 result

$generator->result returns a fresh hash with state, samples produced and sample_rate in Hz.

=head2 reset

$generator->reset returns the object in READY state and invalidates all previous iterators. It preserves configuration.

=head2 state

$generator->state returns READY, ACTIVE or FINISHED.

=head1 AUTHOR

Giacomo Picchiarelli

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2026 Giacomo Picchiarelli. Artistic License 2.0. See F<LICENSE>.

=cut
