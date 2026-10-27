package Ham::RTTY::Result;
use 5.020;
use strict;
use warnings;
use Storable                       qw(dclone);
use Ham::RTTY::_Internal::Validate qw(fail number integer options named_arguments);
use Ham::RTTY::_Internal::Data     qw(plain_data);
use Ham::RTTY::Events              qw(validate_events);
use Ham::RTTY::_Internal::Result;
our $VERSION = '0.001';

sub new {
    my ($class, @pairs) = @_;
    my %args = named_arguments(@pairs);
    options(\%args, qw(text notation events frequency baud warnings complete diagnostics));
    for my $name (qw(text notation)) {
        fail('RTTY_E_ARGUMENT', "$name must be a defined scalar")
            if exists($args{$name}) && (!defined($args{$name}) || ref($args{$name}));
    }
    for my $name (qw(frequency baud)) {
        number($name, $args{$name}, 0, 2**52) if defined $args{$name};
    }
    integer('complete', $args{complete}, 0, 1) if exists $args{complete};
    for my $name (qw(events warnings diagnostics)) {
        next unless exists $args{$name};
        my $kind = $name eq 'warnings' ? 'ARRAY' : 'HASH';
        fail('RTTY_E_ARGUMENT', "$name must contain plain, acyclic data, at most 64 levels deep")
            unless ref($args{$name}) eq $kind && plain_data($args{$name});
    }
    validate_events($args{events}) if exists $args{events};
    for my $warning (@{$args{warnings} // []}) {
        fail('RTTY_E_ARGUMENT', 'Each warning must contain scalar code and message fields')
            if ref($warning) ne 'HASH'
            || !defined($warning->{code})
            || ref($warning->{code})
            || !defined($warning->{message})
            || ref($warning->{message});
    }
    return Ham::RTTY::_Internal::Result->from_owned($class, %{dclone(\%args)});
}

sub has_text     { my ($self) = @_; return length($self->{text}) ? 1 : 0 }
sub has_warnings { my ($self) = @_; return @{$self->{warnings}}  ? 1 : 0 }
sub text         { my ($self) = @_; return $self->{text} }
sub notation     { my ($self) = @_; return $self->{notation} }
sub frequency    { my ($self) = @_; return $self->{frequency} }
sub baud         { my ($self) = @_; return $self->{baud} }
sub complete     { my ($self) = @_; return $self->{complete} }
sub events       { my ($self) = @_; return dclone($self->{events}) }
sub warnings     { my ($self) = @_; return dclone($self->{warnings}) }
sub diagnostics  { my ($self) = @_; return dclone($self->{diagnostics}) }
sub as_hash      { my ($self) = @_; return dclone({%{$self}}) }
1;

=encoding UTF-8

=head1 NAME

Ham::RTTY::Result - a cumulative decoding snapshot with text and diagnostics

=head1 SYNOPSIS

    use strict;
    use warnings;
    use Ham::RTTY;

    my $rtty = Ham::RTTY->new;
    my $result = $rtty->decode_events($rtty->events('SOS'), baud => 45.45);
    print $result->text, "\n";
    for my $warning (@{$result->warnings}) {
        warn "$warning->{code}: $warning->{message}\n";
    }
    my $copy = $result->as_hash;

=head1 DESCRIPTION

Decoder and Detector return cumulative Results. Each snapshot includes all
accepted input so far; later input may revise earlier text. Replace the previous
snapshot rather than appending it.

C<complete> marks finalization; C<has_text> tests for nonempty text. Check
C<warnings> before using the decoded text. Diagnostics describe processing,
not confidence probabilities. Accessors return copies of arrays and hashes;
the object's internal fields are private.

=head1 METHODS

=head2 new

    my $result = Ham::RTTY::Result->new(%fields);

Normally called by the library; constructs a snapshot from these fields:

=over 4

=item * C<text>, C<notation>: defined scalar strings, default empty.

=item * C<events>: canonical event hash, default C<< {unit => 'us', segments => []} >>. See L<Ham::RTTY::Events>.

=item * C<frequency>, C<baud>: undefined by default; otherwise finite numbers in 0..C<2**52>.

=item * C<warnings>: array of hashes with defined scalar C<code> and C<message>; default empty array.

=item * C<complete>: integer 0 or 1; default 0. Explicit C<undef> is invalid.

=item * C<diagnostics>: hash, default empty.

=back

Reference payloads must contain only unblessed arrays/hashes and scalar
leaves, with no cycles and depth at most 64. Input references are copied.
Invalid, unknown or duplicate fields raise C<RTTY_E_ARGUMENT> before copying.
The top-level object hash is locked; direct nested-field mutation is outside
the public interface.

=head2 text

    my $text = $result->text;

Returns the decoded Perl character string. It may be empty or partial.
Unknown event groups become U+FFFD replacement characters while other text
is retained. A replacement character still makes the string nonempty. Use
UTF-8 output encoding when displaying non-ASCII text, for example
C<binmode STDOUT, ':encoding(UTF-8)'>.

=head2 notation

    my $notation = $result->notation;

Returns five-bit numeric codes and shift markers when supplied by a producer.
This field can be empty for audio/event decoding.

=head2 events

    my $events = $result->events;

Returns a deep copy of the retained canonical event sequence. Event decoding
preserves its input representation; audio detection produces SampledEvents.
An empty/rejected result may contain an empty sequence.

=head2 frequency

    my $hz = $result->frequency;

Returns the detector's selected tone in Hz, or C<undef> if absent. For a
supplied tone this is that configured candidate, not an independent
measurement. Event-only decoding has no tone estimate.

=head2 baud

    my $baud = $result->baud;

Returns baud rate, configured, or C<undef> if unavailable.
This is not an automatic speed estimate. See diagnostics for timing source.

=head2 complete

    my $complete = $result->complete;

Returns 0 for a provisional snapshot or 1 after finalization. Empty and
rejected input can also be complete.

=head2 warnings

    my $warnings = $result->warnings;

Returns a deep copy of an array of code/message hashes. See L</WARNINGS>.

=head2 diagnostics

    my $details = $result->diagnostics;

Returns a deep copy. Fields depend on the producer: configured_bit_period
(seconds), measured_bit_period (median observed one-bit run duration in seconds,
undef without evidence), mark_space_level_ratio (accumulated energy ratio,
undef without SPACE energy), framing_error_count, analyzed_samples and
frame_samples. Ratios are not confidence probabilities. Configured baud is
not a measured speed. Check field presence; event-only decoding has no audio
measurements.

=head2 has_text

    my $present = $result->has_text;

Returns 1 when text has nonzero length, otherwise 0. Does not classify accuracy,
replacement characters or warning severity.

=head2 has_warnings

    my $present = $result->has_warnings;

Returns 1 when at least one warning exists, otherwise 0. An empty warning list
is not evidence of error-free radio reception.

=head2 as_hash

    my $fields = $result->as_hash;

Returns a deep copy of all eight stored fields: C<text>, C<notation>, C<events>,
C<frequency>, C<baud>, C<warnings>, C<complete> and C<diagnostics>.
Predicate methods are not extra stored fields. The hash can be serialized
with a suitable encoder such as JSON::PP.

=head1 WARNINGS

RTTY_W_NO_SIGNAL means insufficient tone energy. RTTY_W_FRAMING reports a
SPACE stop or incomplete frame and resynchronisation. RTTY_W_SYMBOL reports
unsupported input substitution or an unassigned received combination.
RTTY_W_WAV_TRAILING means bytes beyond the RIFF boundary were ignored.
No warnings is not proof of correct radio reception.

=head1 SEE ALSO

L<Ham::RTTY::Decoder>, L<Ham::RTTY::Detector>, L<Ham::RTTY::Error>.

=head1 AUTHOR

Giacomo Picchiarelli

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2026 Giacomo Picchiarelli.
Artistic License 2.0. See F<LICENSE> in the source distribution.

=cut
