package Ham::RTTY::Events;
use 5.020;
use strict;
use warnings;
use Exporter 'import';
use Ham::RTTY::_Internal::Validate qw(fail integer number);
our $VERSION   = '0.01';
our @EXPORT_OK = qw(validate_events to_samples to_timed);
my $MAX = 2**52;

sub _validate_header {
    my ($events) = @_;
    my $timed = exists $events->{unit};
    fail('RTTY_E_ARGUMENT', 'Use either unit or sample_rate')
        if $timed && exists $events->{sample_rate};
    if ($timed) {
        fail('RTTY_E_ARGUMENT', 'TimedEvents unit must be us, s or bits')
            if !defined($events->{unit})
            || ref($events->{unit})
            || $events->{unit} !~ /\A(?:us|s|bits)\z/x;
    }
    number('baud', $events->{baud}, 20, 300) if $timed && $events->{unit} eq 'bits';
    if (!$timed) { integer('sample_rate', $events->{sample_rate}, 1000, 384000) }
    return $timed;
}

sub validate_events {
    my ($events, $max_segments) = @_;
    fail('RTTY_E_ARGUMENT', 'Events must contain a segments array')
        unless ref($events) eq 'HASH' && ref($events->{segments}) eq 'ARRAY';
    integer('max_segments', $max_segments //= 100000, 1, 1000000);
    fail('RTTY_E_RESOURCE', 'Event sequence exceeds max_segments')
        if @{$events->{segments}} > $max_segments;
    my $timed = _validate_header($events);
    my $field = $timed ? 'duration' : 'samples';
    my ($previous_state, $total) = ('', 0);
    for my $s (@{$events->{segments}}) {
        fail('RTTY_E_ARGUMENT', 'Invalid segment')
            unless ref($s) eq 'HASH'
            && defined($s->{state})
            && $s->{state} =~ /\A(?:mark|space)\z/x;
        fail('RTTY_E_TIMING', 'Segment states must alternate') if $s->{state} eq $previous_state;
        if ($timed && $events->{unit} ne 'us') { number($field, $s->{$field}, 1e-12, $MAX) }
        else                                   { integer($field, $s->{$field}, 1, $MAX) }
        $total += $s->{$field};
        fail('RTTY_E_RESOURCE', 'Event duration exceeds exact integer range') if $total > $MAX;
        $previous_state = $s->{state};
    }
    return $field;
}

sub _convert {
    my ($events, $ratio, $field, $header) = @_;
    my ($total, $previous) = (0, 0);
    my @out;
    my $input = validate_events($events);
    for my $s (@{$events->{segments}}) {
        $total += $s->{$input};
        fail('RTTY_E_RESOURCE', 'Converted duration exceeds exact integer range')
            if $total * $ratio > $MAX;
        my $end = int($total * $ratio + 0.5);
        fail('RTTY_E_TIMING', 'Resolution would produce a zero-length segment')
            if $end <= $previous;
        push @out, {state => $s->{state}, $field => $end - $previous};
        $previous = $end;
    }
    return {%{$header}, segments => \@out};
}

sub to_samples {
    my ($events, $rate) = @_;
    integer('sample_rate', $rate, 1000, 384000);
    fail('RTTY_E_ARGUMENT', 'Expected TimedEvents') unless validate_events($events) eq 'duration';
    my $scale = $events->{unit} eq 'us' ? 1e-6 : $events->{unit} eq 's' ? 1 : 1 / $events->{baud};
    return _convert($events, $rate * $scale, 'samples', {sample_rate => $rate});
}

sub to_timed {
    my ($events) = @_;
    my $field = validate_events($events);
    my $scale =
          $field eq 'samples'     ? 1 / $events->{sample_rate}
        : $events->{unit} eq 'us' ? 1e-6
        : $events->{unit} eq 's'  ? 1
        :                           1 / $events->{baud};
    return _convert($events, 1_000_000 * $scale, 'duration', {unit => 'us'});
}
1;

=encoding UTF-8

=head1 NAME

Ham::RTTY::Events - validate and convert timed or sampled keying events

=head1 SYNOPSIS

    use strict;
    use warnings;
    use Ham::RTTY::Encoder;
    use Ham::RTTY::Events qw(validate_events to_samples to_timed);

    my $timed = Ham::RTTY::Encoder->new(baud => 50)->events('SOS');
    my $sampled = to_samples($timed, 8000);
    my $timed_again = to_timed($sampled);
    print validate_events($sampled), "\n";  # samples

=head1 EVENT FORMATS

A TimedEvents hash measures duration in integer microseconds:

    { unit => 'us', segments => [
        { state => 'mark',  duration => 60000 },
        { state => 'space', duration => 60000 },
        { state => 'mark',  duration => 180000 },
    ] }

A SampledEvents hash measures duration in sample counts at one sample rate:

    { sample_rate => 8000, segments => [
        { state => 'mark',  samples => 480 },
        { state => 'space', samples => 480 },
        { state => 'mark',  samples => 1440 },
    ] }

C<mark> is binary 1; C<space> is binary 0. Both are active tones. States must alternate within each
sequence. Leading/trailing MARK and an empty C<segments> array are valid.
Timed units may also be C<s> (seconds) or C<bits> (requiring C<baud>, 20..300). Fractional durations are positive finite values. C<validate_events($events, $max_segments)> bounds runs, default 100000, integer 1..1000000.

Use C<unit> or C<sample_rate>, never both. Rates are integer Hz in
1000..384000. Each segment duration/count is a positive integer, and the
sum is at most C<2**52> in the sequence's units. Input hashes are not modified.

=head1 FUNCTIONS

Nothing is exported automatically. Import the functions you use explicitly.

=head2 validate_events

    my $field = validate_events($events);

Validates the header and every segment. Returns C<duration> for TimedEvents
or C<samples> for SampledEvents. It returns no converted copy. Invalid shape
or values raise C<RTTY_E_ARGUMENT>, repeated adjacent states raise
C<RTTY_E_TIMING>, and an excessive total raises C<RTTY_E_RESOURCE>.

=head2 to_samples

    my $sampled = to_samples($timed, $sample_rate);

Requires TimedEvents and a rate in integer Hz (1000..384000). Returns a new
SampledEvents hash. To change the rate of sampled events, convert to timed
events first; this function is not an audio resampler.

=head2 to_timed

    my $timed = to_timed($sampled);

Requires SampledEvents and returns a new TimedEvents hash in microseconds.
The sample rate is taken from the input header.

=head1 ROUNDING AND RESOLUTION

Conversions round cumulative boundaries to the nearest integer, with halves
upward, then subtract consecutive boundaries to obtain durations. They do
not round each duration independently. A round trip can lose precision;
use the original event sequence when exact source timing is needed.

A conversion that produces a zero-length segment raises C<RTTY_E_TIMING>.
Use a finer sample resolution or longer events. Converted total duration
must also remain at most C<2**52>, otherwise C<RTTY_E_RESOURCE> is thrown.
Input format/type errors raise C<RTTY_E_ARGUMENT>.

=head1 SEE ALSO

L<Ham::RTTY::Encoder/events>, L<Ham::RTTY::Generator>, L<Ham::RTTY::Decoder>.

=head1 AUTHOR

Giacomo Picchiarelli

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2026 Giacomo Picchiarelli.
Artistic License 2.0. See F<LICENSE> in the source distribution.

=cut
