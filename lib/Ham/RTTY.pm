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
our $VERSION = '0.01';

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

Use the make program supplied with your Perl installation; on Windows this
may be C<gmake>. For a user-owned destination, configure with
C<perl Makefile.PL INSTALL_BASE=/your/install/directory> and include its
C<lib/perl5> directory in C<PERL5LIB>.

A checkout can be used without installing: run C<perl -Ilib script.pl> from
the repository root. Read this reference with C<perldoc lib/Ham/RTTY.pm>, or
C<perldoc Ham::RTTY> after installation. The distribution is C<Ham-RTTY>;
the Perl package is C<Ham::RTTY>.

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

    my $decoder = $rtty->decoder(%options);

Returns a fresh L<Ham::RTTY::Decoder>. Generation defaults are not receiver
hints.

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

    my $stats = $rtty->generate_wav($text, $handle, %options);

Writes PCM WAV to a caller-owned open handle and returns a state/samples hash.
Generation options plus bits (8, 16 default, 24), C<block_size> (4096 default)
and C<max_bytes> (64000000 default) apply. Output is mono. The handle need not
seek and remains open. An I/O failure can leave partial bytes.

=head2 generate_midi

    my $count = $rtty->generate_midi($text, $handle, %options);

Writes a type-0 MIDI debug rendering to a caller-owned handle, returning bytes
written. Encoder options and L<Ham::RTTY::MIDI/new> options apply. MIDI is a
two-note visual/debug rendering, not radio audio.

=head2 write_wav

    my $stats = $rtty->write_wav($text, $path, %options);

Owns and closes a WAV file; returns state/samples. Options are those of
generate_wav plus overwrite (integer 0 or 1, default 0). See file ownership
below.

=head2 write_midi

    my $count = $rtty->write_midi($text, $path, %options);

Owns and closes a MIDI file; returns bytes written. Options are those of
generate_midi plus overwrite (integer 0 or 1, default 0).

=head2 wav_bytes

    my $bytes = $rtty->wav_bytes($text, %options);

Returns binary PCM WAV bytes in memory, with generate_wav options. Never
text-encode these bytes.

=head2 midi_bytes

    my $bytes = $rtty->midi_bytes($text, %options);

Returns binary type-0 MIDI bytes in memory, with generate_midi options.

=head2 decode_wav

    my $result = $rtty->decode_wav($handle, %options);

Returns a complete Result from a caller-owned seekable binary WAV handle.
Detector options except C<sample_rate> apply; rate comes from the header.
Additional Audio options are stereo (mix default, left, right), C<max_bytes>
(64000000 default), C<block_samples> (4096 default). Ranges follow
L<Ham::RTTY::Audio/new>. The reader preserves trailing-RIFF warnings.

=head2 decode_wav_bytes

    my $result = $rtty->decode_wav_bytes($bytes, %options);

Returns a complete Result from binary WAV bytes in memory. Options follow
decode_wav; undefined, reference or non-byte input raises C<RTTY_E_ARGUMENT>.

=head2 read_wav

    my $result = $rtty->read_wav($path, %options);

opens, receives and closes a WAV file. Options follow decode_wav. It retains
bounded decisions, not the full raw sample array. Inspect Result warnings even
when text is nonempty.

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

Path helpers own their handles. By default output uses exclusive creation;
existing files are protected. overwrite => 1 writes a temporary sibling,
closes it and renames it onto the destination. Failed generation preserves the
previous file. Symlink and nonregular replacement destinations are rejected.
Replacement retains destination permissions. Filesystem durability and racing
third-party changes cannot be guaranteed. Caller-owned handles remain open;
stdout and other stream writes cannot be rolled back.

=head1 ERRORS

Unknown, duplicate, odd or invalid options raise C<RTTY_E_ARGUMENT>.
Unsupported characters/notation raise C<RTTY_E_SYMBOL>. Invalid event timing
or conversion resolution raises C<RTTY_E_TIMING>. Limits raise
C<RTTY_E_RESOURCE>; invalid lifecycle raises C<RTTY_E_STATE>; I/O failures
raise C<RTTY_E_IO>. Malformed WAV uses C<RTTY_E_WAV_FORMAT> or
C<RTTY_E_WAV_TRUNCATED>. Catch L<Ham::RTTY::Error> objects and inspect code,
message and context. Recoverable reception problems use RTTY_W_* warnings in
L<Ham::RTTY::Result>.

=head1 AUTHOR

Giacomo Picchiarelli

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2026 Giacomo Picchiarelli.
Artistic License 2.0. See F<LICENSE> in the source distribution.

=cut
