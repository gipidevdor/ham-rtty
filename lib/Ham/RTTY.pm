package Ham::RTTY;
use 5.020;
use strict;
use warnings;
use Ham::RTTY::Encoder;
use Ham::RTTY::Decoder;
use Ham::RTTY::Generator;
use Ham::RTTY::Detector;
use Ham::RTTY::Audio;
use Ham::RTTY::MIDI;
use Ham::RTTY::Events              ();
use Ham::RTTY::_Internal::IO       qw(with_file);
use Ham::RTTY::_Internal::Validate qw(fail options named_arguments);
our $VERSION = '0.001';

sub new {
    my ($class, @pairs) = @_;
    my %args = named_arguments(@pairs);
    options(\%args,
        qw(baud stop_bits variant usos lenient leading_idle trailing_idle max_segments mark shift reverse sample_rate amplitude backend max_samples)
    );
    my %encoder = map { exists($args{$_}) ? ($_ => $args{$_}) : () }
        qw(baud stop_bits variant usos lenient leading_idle trailing_idle max_segments);
    my %generator = map { exists($args{$_}) ? ($_ => $args{$_}) : () }
        qw(mark shift reverse sample_rate amplitude backend max_samples);
    Ham::RTTY::Encoder->validate(%encoder);
    Ham::RTTY::Generator->validate(%generator);
    return bless {encoder => \%encoder, generator => \%generator}, $class;
}

sub _encoder {
    my ($self, $args) = @_;
    my %overrides =
        map { exists($args->{$_}) ? ($_ => delete $args->{$_}) : () }
        qw(baud stop_bits variant usos lenient leading_idle trailing_idle max_segments);
    my %config = (%{$self->{encoder}}, %overrides);
    return Ham::RTTY::Encoder->new(%config);
}

sub encoder {
    my ($self, @pairs) = @_;
    my %args    = named_arguments(@pairs);
    my $encoder = $self->_encoder(\%args);
    options(\%args);
    return $encoder;
}

sub encode {
    my ($self, $text, @pairs) = @_;
    return $self->encoder(@pairs)->encode($text);
}

sub bits {
    my ($self, $text, @pairs) = @_;
    return $self->encoder(@pairs)->bits($text);
}

sub events {
    my ($self, $text, @pairs) = @_;
    return $self->encoder(@pairs)->events($text);
}

sub sampled_events {
    my ($self, $text, @pairs) = @_;
    my %args = named_arguments(@pairs);
    my $rate = delete($args{sample_rate}) // $self->{generator}{sample_rate} // 16000;
    return Ham::RTTY::Events::to_samples($self->events($text, %args), $rate);
}

sub decoder {
    my ($self, @pairs) = @_;
    return Ham::RTTY::Decoder->new(@pairs);
}

sub decode {
    my ($self, $notation, @pairs) = @_;
    return $self->decoder(@pairs)->decode($notation);
}

sub decode_events {
    my ($self, $events, @pairs) = @_;
    my $decoder = $self->decoder(@pairs);
    $decoder->feed($events);
    return $decoder->finish;
}

sub detector {
    my ($self, @pairs) = @_;
    my %args = named_arguments(@pairs);
    $args{sample_rate} //= $self->{generator}{sample_rate} // 16000;
    $args{backend}     //= $self->{generator}{backend}     // 'perl';
    return Ham::RTTY::Detector->new(%args);
}

sub decode_samples { my ($self, @args) = @_; return $self->_decode_samples(@args) }

sub _decode_samples {
    my ($self, $values, @pairs) = @_;
    Ham::RTTY::_Internal::Validate::samples($values, 100000000);
    my $detector = $self->detector(@pairs);
    for (my $offset = 0; $offset < @{$values}; $offset += 4096) {
        my $end = $offset + 4095;
        $end = $#{$values} if $end > $#{$values};
        $detector->feed([@{$values}[$offset .. $end]]);
    }
    my $result = $detector->finish;
    return $result;
}

sub generator {
    my ($self, @pairs) = @_;
    my %args   = named_arguments(@pairs);
    my %config = (%{$self->{generator}}, %args);
    return Ham::RTTY::Generator->new(%config);
}

sub _generation {
    my ($self, $text, $args) = @_;
    my $encoder   = $self->_encoder($args);
    my %overrides = map { exists($args->{$_}) ? ($_ => delete $args->{$_}) : () }
        qw(mark shift reverse sample_rate amplitude backend max_samples);
    return ($encoder->events($text), $self->generator(%overrides));
}

sub stream_samples {
    my ($self, $text, @pairs) = @_;
    my %args = named_arguments(@pairs);
    my ($events, $generator) = $self->_generation($text, \%args);
    options(\%args, 'block_size');
    return $generator->stream($events, $args{block_size});
}

sub samples {
    my ($self, $text, @pairs) = @_;
    my %args = named_arguments(@pairs);
    my ($events, $generator) = $self->_generation($text, \%args);
    options(\%args);
    return $generator->generate($events);
}

sub wav_bytes {
    my ($self, $text, @pairs) = @_;
    my $bytes = '';
    open my $handle, '>:raw', \$bytes or fail('RTTY_E_IO', 'Cannot open in-memory WAV output');
    $self->generate_wav($text, $handle, @pairs);
    close $handle or fail('RTTY_E_IO', 'Cannot close in-memory WAV output');
    return $bytes;
}

sub decode_wav_bytes {
    my ($self, $bytes, @pairs) = @_;
    fail('RTTY_E_ARGUMENT', 'WAV bytes must be a defined scalar')
        if !defined($bytes) || ref($bytes);
    fail('RTTY_E_ARGUMENT', 'WAV bytes cannot contain Unicode characters above U+00FF')
        unless utf8::downgrade($bytes, 1);
    open my $handle, '<:raw', \$bytes or fail('RTTY_E_IO', 'Cannot open in-memory WAV input');
    my $result = $self->decode_wav($handle, @pairs);
    close $handle or fail('RTTY_E_IO', 'Cannot close in-memory WAV input');
    return $result;
}

sub midi_bytes {
    my ($self, $text, @pairs) = @_;
    my %args    = named_arguments(@pairs);
    my $encoder = $self->_encoder(\%args);
    return Ham::RTTY::MIDI->new(%args)->encode($encoder->events($text));
}

sub write_wav {
    my ($self, $text, $path, @pairs) = @_;
    my %args = named_arguments(@pairs);
    my $overwrite =
        Ham::RTTY::_Internal::Validate::integer('overwrite', delete($args{overwrite}) // 0, 0, 1);
    return with_file($path, 'write', sub { $self->generate_wav($text, $_[0], %args) }, $overwrite);
}

sub write_midi {
    my ($self, $text, $path, @pairs) = @_;
    my %args = named_arguments(@pairs);
    my $overwrite =
        Ham::RTTY::_Internal::Validate::integer('overwrite', delete($args{overwrite}) // 0, 0, 1);
    return with_file($path, 'write', sub { $self->generate_midi($text, $_[0], %args) }, $overwrite);
}

sub read_wav {
    my ($self, $path, @pairs) = @_;
    return with_file($path, 'read', sub { $self->decode_wav($_[0], @pairs) });
}

sub generate_wav {
    my ($self, $text, $fh, @pairs) = @_;
    my %args = named_arguments(@pairs);
    my ($events, $gen) = $self->_generation($text, \%args);
    options(\%args, qw(bits max_bytes block_size));
    my $rate    = $gen->{sample_rate};
    my $sampled = Ham::RTTY::Events::to_samples($events, $rate);
    my $count   = 0;
    $count += $_->{samples} for @{$sampled->{segments}};
    my $audio = Ham::RTTY::Audio->new(
        backend => $gen->{backend},
        exists($args{max_bytes}) ? (max_bytes => $args{max_bytes}) : ()
    );
    my $next   = $gen->stream($sampled, $args{block_size});
    my $writer = $audio->writer(
        $fh,
        sample_rate  => $rate,
        sample_count => $count,
        bits         => $args{bits} // 16
    );
    while (my $block = $next->()) { $writer->feed($block) }
    return $writer->finish;
}

sub generate_midi {
    my ($self, $text, $fh, @pairs) = @_;
    my %args    = named_arguments(@pairs);
    my $encoder = $self->_encoder(\%args);
    return Ham::RTTY::MIDI->new(%args)->write($fh, $encoder->events($text));
}

sub decode_wav { my ($self, @args) = @_; return $self->_decode_wav(@args) }

sub _decode_wav {
    my ($self, $fh, @pairs) = @_;
    my %args = named_arguments(@pairs);
    options(\%args,
        qw(mark shift reverse baud variant usos atc search min_frequency max_frequency frequency_step max_frames max_segments stereo max_bytes backend block_samples)
    );
    $args{backend} //= $self->{generator}{backend} // 'perl';
    my %audio = map { exists($args{$_}) ? ($_ => delete $args{$_}) : () }
        qw(stereo max_bytes block_samples);
    $audio{backend} = $args{backend};
    my $reader   = Ham::RTTY::Audio->new(%audio)->reader($fh);
    my $detector = Ham::RTTY::Detector->new(%args, sample_rate => $reader->{sample_rate});
    while (my $block = $reader->{next}->()) { $detector->feed($block) }
    my $result = $detector->finish;

    if (@{$reader->{warnings}}) {
        my $snapshot = $result->as_hash;
        push @{$snapshot->{warnings}}, @{$reader->{warnings}};
        $result = Ham::RTTY::Result->new(%{$snapshot});
    }
    return $result;
}
1;

=encoding UTF-8

=head1 NAME

Ham::RTTY - ITA2 text, start-stop timing, AFSK audio and MIDI tools

=head1 SYNOPSIS

    use strict;
    use warnings;
    use Ham::RTTY;

    my $rtty = Ham::RTTY->new(baud => 50);
    print $rtty->encode('CQ 123'), "\n";
    my $wav = $rtty->wav_bytes('CQ TEST');
    my $result = $rtty->decode_wav_bytes($wav, baud => 50);
    print $result->text, "\n";

=head1 DESCRIPTION

Ham::RTTY converts text to ITA2, start-stop events, AFSK samples, PCM WAV and
MIDI. It receives notation, events and recorded audio.

Requires Perl 5.20 or later and core modules; PDL 2.081 or later is optional.
Playback, capture and radio-device control belong to the calling application.

=head1 INSTALLATION AND DOCUMENTATION

From an extracted distribution or repository root, run:

    perl Makefile.PL
    make
    make test
    make install

Use the make program for your Perl installation; on Windows this may be
C<gmake>. Installation needs permission to write to Perl's library directory.
For a user-owned destination, configure with
C<perl Makefile.PL INSTALL_BASE=/your/install/directory> and add its
C<lib/perl5> directory to C<PERL5LIB> when running applications.

A source checkout can be used without installing: run scripts as
C<perl -Ilib script.pl> from the repository root. Read this reference with
C<perldoc lib/Ham/RTTY.pm>, or C<perldoc Ham::RTTY> after installation.
The distribution name is C<Ham-RTTY>; the Perl package is C<Ham::RTTY>.

=head1 TERMS AND DATA

B<Baud> is the number of transmitted bits per second. One bit lasts
C<1 / baud> seconds. Frames contain one start bit, five data bits and a
configurable stop duration. LTRS and FIGS select the ITA2 character table.

B<Sample rate> is samples per second, in Hz. Normalized mono samples are
finite Perl numbers in [-1,1]. Sample arrays contain these values; PCM byte
strings contain quantized 8-, 16- or 24-bit values.

B<Events> describe alternating MARK (1) and SPACE (0) runs. Both states
represent active tones. L<Ham::RTTY::Events> defines timed and sampled event
formats and their conversion rules.

Text is a Perl character string. Decode external UTF-8 before calling the
library; use C<use utf8> for non-ASCII literals in Perl source. WAV and MIDI
strings are binary bytes and must not be text-encoded.

=head1 OPTIONS AND DEFAULTS

Named options are name/value pairs. Unknown or duplicate names and odd-length
lists raise C<RTTY_E_ARGUMENT>. Numeric values must be finite; documented
ranges include both endpoints. Optional undefined values use defaults.

Generation defaults are held by the facade. Per-call overrides apply to
that operation only. Encoder and Generator document their accepted options
and ranges. Reception has separate configuration: only the facade's sample
rate and backend preference are inherited. WAV reception takes the sample
rate from the file header.

=head1 METHODS

=head2 new

    my $rtty = Ham::RTTY->new(%generation_options);

Validates Encoder and Generator defaults without opening files. Options are
C<baud>, C<stop_bits>, C<variant>, C<usos>, C<lenient>, C<leading_idle>,
C<trailing_idle>, C<max_segments>, C<mark>, C<shift>, C<reverse>,
C<sample_rate>, C<amplitude>, C<backend> and C<max_samples>. Defaults and
ranges follow L<Ham::RTTY::Encoder/new> and
L<Ham::RTTY::Generator/new>. Per-call overrides do not modify defaults.
Reception needs its own explicit tone/baud settings; only sample rate and
backend are inherited.

=head2 encoder

    my $encoder = $rtty->encoder(%options);

Returns a fresh L<Ham::RTTY::Encoder> with generation defaults and per-call
overrides. Unknown options raise C<RTTY_E_ARGUMENT>.

=head2 decoder

    my $decoder = $rtty->decoder(%decoder_options);

Returns a fresh L<Ham::RTTY::Decoder> with explicit decoding options only.
Use C<feed>, C<result>, C<finish> and C<reset> for successive event blocks.

=head2 generator

    my $generator = $rtty->generator(%options);

Returns a fresh READY L<Ham::RTTY::Generator> with stored defaults and
per-call overrides.

=head2 detector

    my $detector = $rtty->detector(%options);

Returns a fresh L<Ham::RTTY::Detector>. C<sample_rate> and backend default to
generation settings; other options follow L<Ham::RTTY::Detector/new>. Reception uses
configured baud (default 45.45), never automatic baud detection.

=head2 encode

    my $notation = $rtty->encode($text, %encoder_options);

Returns five-bit numeric notation with shift markers. See
L<Ham::RTTY::Encoder/encode>. Each call starts a new message.

=head2 decode

    my $text = $rtty->decode($notation, %decoder_options);

Returns text from five-bit codes and shift markers. Invalid syntax raises
C<RTTY_E_SYMBOL>. See L<Ham::RTTY::Decoder/decode>.

=head2 bits

    my $bits = $rtty->bits($text, %encoder_options);

Returns framed 0/1 transmission bits. Fractional 1.5 stop is represented by
two 1 digits; events preserve exact timing. See L<Ham::RTTY::Encoder/bits>.

=head2 events

    my $events = $rtty->events($text, %encoder_options);

Returns alternating MARK/SPACE integer-microsecond runs. See
L<Ham::RTTY::Events>.

=head2 sampled_events

    my $sampled = $rtty->sampled_events($text, sample_rate => 8000, %encoder_options);

Returns sampled runs; rate defaults to stored generation rate (16000 Hz).
Conversion rounds cumulative boundaries.

=head2 decode_events

    my $result = $rtty->decode_events($events, %decoder_options);

Feeds and finalizes an event decoder, returning an independent complete
Result. It does not inherit generation baud.

=head2 samples

    my $samples = $rtty->samples($text, %generation_options);

Returns a normalized mono sample array. Encoder and Generator options may be
overridden. C<max_samples> bounds total generation; collected Perl arrays
require more memory than PCM.

=head2 stream_samples

    my $next = $rtty->stream_samples($text, block_size => 4096, %generation_options);

Returns an iterator yielding sample arrays then undef at EOF. Block size is
integer 1..1000000. Waveform phase is continuous across tones and blocks.

=head2 decode_samples

    my $result = $rtty->decode_samples($array, %detector_options);

Returns a finalized Result, feeding 4096-sample blocks. Input is finite
normalized mono samples in [-1,1], at most 100000000 samples. The actual
C<sample_rate> is required for external arrays; otherwise stored generation
rate is used.

=head2 generate_wav

    my $stats = $rtty->generate_wav($text, $handle, %wav_options);

Writes a mono PCM WAV to an open binary output handle and returns writer
statistics as described under L</write_wav>. Accepts all generation options,
C<block_size> (4096; 1..1000000), C<bits> (8, 16 or 24; default 16), and
C<max_bytes> (64000000; integer 44..4294967295). The byte ceiling includes
header and padding; the sample ceiling applies separately.
The handle need not seek and remains owned by the caller.

=head2 generate_midi

    my $count = $rtty->generate_midi($text, $handle, %options);

Writes a type-0 MIDI debug rendering to a caller-owned handle, returning bytes
written. Encoder options and L<Ham::RTTY::MIDI/new> options apply. MIDI is a
two-note visual/debug rendering, not radio audio.

=head2 write_wav

    my $stats = $rtty->write_wav($text, $path, %wav_options);

Creates and closes a mono WAV file. Returns
C<< {state => 'FINISHED', samples => $written_count} >>. Accepts
L</generate_wav> options plus C<overwrite> (0 or 1; default 0).
See L</FILE OWNERSHIP AND REPLACEMENT> for file handling and failure behavior.

=head2 write_midi

    my $count = $rtty->write_midi($text, $path, %midi_options);

Creates and closes a type-0 MIDI file; returns the file size in bytes.
Accepts L</generate_midi> options plus C<overwrite> (default 0).
MIDI contains notes and timing, not rendered audio.

=head2 wav_bytes

    my $bytes = $rtty->wav_bytes($text, %wav_options);

Returns a binary WAV scalar. Accepts L</generate_wav> options, without
C<overwrite>. Collects the entire encoded file in memory.

=head2 midi_bytes

    my $bytes = $rtty->midi_bytes($text, %midi_options);

Returns a binary MIDI scalar. Accepts L</generate_midi> options, without
C<overwrite>. Collects the entire encoded file in memory.

=head2 decode_wav

    my $result = $rtty->decode_wav($handle, %options);

Returns a complete Result from a caller-owned seekable binary WAV handle.
Detector options except C<sample_rate> apply; rate comes from the header.
Additional Audio options are stereo (mix default, left, right), C<max_bytes>
(64000000 default), C<block_samples> (4096 default). Ranges follow
L<Ham::RTTY::Audio/new>. The reader preserves trailing-RIFF warnings.

=head2 decode_wav_bytes

    my $result = $rtty->decode_wav_bytes($bytes, %reception_options);

Reads a binary WAV scalar and returns a finalized Result. Accepts
L</decode_wav> options. The complete WAV byte string must already be in memory.

=head2 read_wav

    my $result = $rtty->read_wav($path, %reception_options);

Opens, decodes and closes a WAV file; returns a finalized Result. Accepts
L</decode_wav> options. Empty or uncertain reception is represented in the
Result; invalid paths, unsupported files and resource errors throw exceptions.

=head1 POLARITY AND TIMING

MARK is binary 1, SPACE binary 0; idle is continuous MARK. Default audio MARK
is 2125 Hz and SPACE is 2295 Hz. reverse swaps the audio frequencies. USB
preserves audio frequency ordering; LSB reverses RF ordering relative to
audio. Match receiver/radio polarity to the transmitted signal rather than
assuming a universal radio setting. Direct FSK electrical keying is outside
this toolkit. The transmitter uses continuous phase without raised-cosine
frequency-transition shaping.

A frame has one SPACE start, five data bits LSB first and MARK stop. Events
preserve 1, 1.5 or 2 stop bits. Receiver sampling uses a configured bit
period; C<measured_bit_period> is diagnostic evidence, not an automatic speed
mode. No simultaneous stations, automatic baud/shift identification,
equalisation or diversity are implemented. Off-air performance remains a
separate gate.

=head1 OPTIONAL PDL BACKEND

perl is the default. auto selects pdl by availability only, never by measured
speed. Explicit pdl fails with C<RTTY_E_ARGUMENT> when unavailable. PDL
broadcasts both tone projections together and accelerates sample synthesis and
PCM conversion. UART state, segmentation, validation and acquisition control
remain Perl. Small windows and conversion overhead can make PDL slower.
Floating-point roundoff can differ across backends; decoded text must agree.

=head1 FILE OWNERSHIP AND REPLACEMENT

Path methods open and close their own handles. Paths must be nonempty strings
without NUL characters. Parent directories must already exist. Existing
output paths, including symlinks, are rejected by default with C<RTTY_E_IO>.
On failure, a newly created output is closed and removal is attempted.

With C<overwrite =E<gt> 1>, output is first written to a temporary file in the
same directory and renamed after successful generation and close. Failure
before replacement preserves the old destination and attempts temporary-file
cleanup. Existing regular-file permission bits are preserved. Symbolic-link
destinations, including dangling links, are rejected with C<RTTY_E_IO> when
detected during preparation. These checks and the final rename are separate
operations: a concurrently substituted destination can still be replaced.
Use an output directory whose entries are not being changed by other writers.
A new path follows the process umask. Replacement creates a new file identity;
ownership, ACLs and other hard links are not transferred. Replacement can
fail if directory permissions or the operating system prevent rename.

Handle methods never close caller-owned handles. Set binary mode when
opening WAV/MIDI files and check C<close> errors yourself:

    open my $out, '>:raw', 'handle-demo.wav' or die $!;
    $rtty->generate_wav('SOS', $out);
    close $out or die $!;

Unlike path methods, this C<open> truncates an existing file immediately.
A failed handle write can leave partial output for the caller to discard.

=head1 RESULTS AND WARNINGS

Reception returns L<Ham::RTTY::Result>. C<text> may be empty, partial or contain
U+FFFD replacement characters. C<has_text> only tests nonempty text.
C<complete> means finalized, not correct. C<warnings> returns an array of
C<< {code => ..., message => ...} >> hashes. Inspect it even when text exists.
C<frequency> and C<baud> can be undefined when a producer has no corresponding measurement or setting.

Result reference fields are copied on input and access. Diagnostic fields
explain analysis; they are not confidence scores. L<Ham::RTTY::Result> documents
every accessor, warning code and diagnostic field.

=head1 ERRORS

Failures throw L<Ham::RTTY::Error>. Capture C<$@> immediately after C<eval>:

    my $ok = eval { $rtty->encode('CQ!'); 1 };
    if (!$ok) {
        my $error = $@;
        if (ref($error) && $error->isa('Ham::RTTY::Error')) {
            warn $error->code . ': ' . $error->message . "\n";
        }
        else { die $error; }
    }

=over 4

=item * C<RTTY_E_ARGUMENT>: invalid option, value or data shape.

=item * C<RTTY_E_SYMBOL>: unsupported text or invalid textual ITA2 codes.

=item * C<RTTY_E_TIMING>: invalid event alternation or insufficient sample/tick resolution.

=item * C<RTTY_E_WAV_FORMAT>: unsupported or inconsistent WAV format.

=item * C<RTTY_E_WAV_TRUNCATED>: insufficient bytes for the declared structure.

=item * C<RTTY_E_IO>: open, read, write, seek, close or replacement failure.

=item * C<RTTY_E_RESOURCE>: configured or format size/history limit exceeded.

=item * C<RTTY_E_STATE>: invalid incremental lifecycle or invalidated iterator.

=item * C<RTTY_E_INTERNAL>: unspecified/internal failure.

=back

Validation failures preserve decoder/detector history and writer counters.
I/O failures can leave partial output; a WAV writer enters C<FAILED> and must
be replaced. No error code or successful call guarantees error-free reception.

=head1 SEE ALSO

L<Ham::RTTY::Encoder>, L<Ham::RTTY::Decoder>, L<Ham::RTTY::Events>,
L<Ham::RTTY::Generator>, L<Ham::RTTY::Detector>, L<Ham::RTTY::Audio>,
L<Ham::RTTY::MIDI>, L<Ham::RTTY::Result>, L<Ham::RTTY::Error>.

In the source distribution, F<docs/usage.md> is a task guide and
F<examples/workflows.pl> is a runnable tour using temporary files.
F<docs/verification.md> records dated checks and their limits.

=head1 AUTHOR

Giacomo Picchiarelli

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2026 Giacomo Picchiarelli.
Artistic License 2.0. See F<LICENSE> in the source distribution.

=cut
