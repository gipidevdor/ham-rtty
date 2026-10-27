package Ham::RTTY::Result;
use 5.020;
use strict;
use warnings;
use Storable                       qw(dclone);
use Ham::RTTY::_Internal::Validate qw(fail number integer options named_arguments);
use Ham::RTTY::_Internal::Data     qw(plain_data);
use Ham::RTTY::Events              qw(validate_events);
use Ham::RTTY::_Internal::Result;
our $VERSION = '0.01';

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

    my $cw = Ham::RTTY->new;
    my $result = $cw->decode_events($cw->events('SOS'), baud => 20);
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

Returns dot/dash groups with spaces between letters and C</> between words.
An implausible event mark may appear as C<?> for diagnostic purposes;
therefore this field is not always valid input for strict textual decoding.

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

Returns character speed, configured or estimated, or C<undef> if unavailable.
This is not effective Farnsworth speed. See diagnostics for timing source.

=head2 complete

    my $complete = $result->complete;

Returns 0 for a provisional snapshot or 1 after finalization. Empty and
rejected input can also be complete.

=head2 warnings

    my $warnings = $result->warnings;

Returns a deep copy of an array of code/message hashes. See L</WARNINGS>.

=head2 diagnostics

    my $details = $result->diagnostics;

Returns a deep copy of the diagnostics hash. Fields depend on how far
analysis progressed and can be absent. Current producer fields are:

=over 4

=item * C<dot_us>: configured/estimated dot duration in microseconds.

=item * C<timing_source>: C<configured> or C<estimated> for character timing.

=item * C<contrast>: keyed-envelope separation, C<(peak - floor) / peak>.

=item * C<purity>: projected tone energy divided by windowed energy of the filtered channel. A matched, well-resolved pure Hann-windowed tone is about 0.67; this is not a probability or a scale normalized to 1.

=item * C<frame_samples>: full detector frame length in samples.

=item * C<analyzed_samples>: total accepted input sample count. In a preview, a partial frame can still be pending and excluded from spectral analysis.

=item * C<filter_bandwidth_hz>: configured full half-power width of one biquad section. The cascade has a narrower response; this field is not station separation or frequency accuracy.

=item * C<filter_sections>: number of cascaded band-pass biquads per candidate (currently 2).

=item * C<mark_snr_db>: configured minimum mean mark/local-noise power ratio in dB, before glitch removal. This is not calibrated radio SNR.

=item * C<frequency_grid_step_hz>: search candidate step, or 0 for a configured tone. This is not spectral resolution or an error bound.

=back

Rejected input may contain only the diagnostic that explained rejection.
Applications should check field existence rather than assuming a fixed set.

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

Warnings describe reception evidence and are separate from thrown errors:

=over 4

=item C<RTTY_W_NO_SIGNAL>

No usable frames or insufficient energy. Check the recording, input rate,
selected channel and tone/search band.

=item C<RTTY_W_NOT_CW>

Envelope contrast, spectral purity or mark count did not meet detector
criteria. Noise, an unkeyed tone and very short messages can produce this.
Changing thresholds does not establish that the input is Morse.

=item C<RTTY_W_NO_TIMING>

No usable mark timing was found. Check event units and supply WPM if known.

=item C<RTTY_W_TIMING_AMBIGUOUS>

One mark length cannot distinguish dots from dashes. Supply character WPM.
The event decoder can retain a provisional interpretation; the audio
detector suppresses text for this ambiguity.

=item C<RTTY_W_UNRELIABLE>

The detector suppressed text because automatic mark timing was ambiguous.
Review the accompanying timing warning and provide a speed hint if known.

=item C<RTTY_W_TIMING>

A mark is outside timing tolerance. Text can contain a replacement character.

=item C<RTTY_W_SYMBOL>

An event-derived group has no unambiguous symbol. That group becomes U+FFFD.

=item C<RTTY_W_SPACING_AMBIGUOUS>

Repeated internal long gaps may indicate unknown Farnsworth spacing, or
C<effective_baud> exceeds estimated character speed and ordinary spacing was
used. Read the message for the applicable case; supply correct timing hints.
Leading/trailing silence alone does not produce this warning.

=item C<RTTY_W_WAV_TRAILING>

Bytes after the RIFF boundary were ignored. Audio within RIFF was processed;
check the file's source if the extra data was unexpected. Raw Audio readers
expose this in metadata; facade reception propagates it into the Result.

=item C<RTTY_W_INTERFERENCE>

Carrier intervals, short implausible marks or unsupported outer activity
were excluded during audio reception. It does not certify that every
remaining group is CW; damaged legitimate characters may also have been
excluded. Symbolic/event decoding does not apply these audio-specific
exclusions.

=back

=head1 SEE ALSO

L<Ham::RTTY::Decoder>, L<Ham::RTTY::Detector>, L<Ham::RTTY::Error>.

=head1 AUTHOR

Giacomo Picchiarelli

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2026 Giacomo Picchiarelli.
Artistic License 2.0. See F<LICENSE> in the source distribution.

=cut
