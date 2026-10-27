package Ham::RTTY::Audio;
use 5.020;
use strict;
use warnings;
use Ham::RTTY::_Internal::WavWriter;
use Ham::RTTY::_Internal::IO       qw(read_exact write_bytes with_file);
use Scalar::Util                 qw(openhandle);
use Ham::RTTY::_Internal::Validate qw(fail integer options samples named_arguments);
use Ham::RTTY::_Internal::Backend;
our $VERSION = '0.001';

sub new {
    my ($class, @pairs) = @_;
    my %args = named_arguments(@pairs);
    options(\%args, qw(max_bytes stereo block_samples backend));
    my $policy = $args{stereo} // 'mix';
    fail('RTTY_E_ARGUMENT', 'stereo must be left, right or mix')
        unless $policy =~ /\A(?:left|right|mix)\z/x;
    return bless {
        stereo        => $policy,
        backend       => Ham::RTTY::_Internal::Backend::resolve($args{backend}),
        max_bytes     => integer('max_bytes',     $args{max_bytes}     // 64000000, 44, 4294967295),
        block_samples => integer('block_samples', $args{block_samples} // 4096,     1,  1000000)
    }, $class;
}

sub _chunks {
    my ($fh, $size) = @_;
    my ($format, $data);
    my $pos = 12;
    while ($pos < $size) {
        fail('RTTY_E_WAV_TRUNCATED', 'Incomplete chunk header') if $size - $pos < 8;
        my ($id, $len) = unpack('a4V', read_exact($fh, 8));
        $pos += 8;
        my $padded = $len + ($len % 2);
        fail('RTTY_E_WAV_TRUNCATED', 'Chunk exceeds RIFF boundary') if $padded > $size - $pos;
        if ($id eq 'fmt ') {
            fail('RTTY_E_WAV_FORMAT', 'Duplicate or short fmt chunk') if $format || $len < 16;
            $format = [unpack('vvVVvv', read_exact($fh, 16))];
        }
        elsif ($id eq 'data') {
            fail('RTTY_E_WAV_FORMAT', 'Multiple data chunks are unsupported') if $data;
            $data = [$pos, $len];
        }
        $pos += $padded;
        seek($fh, $pos, 0) or fail('RTTY_E_IO', 'Cannot skip WAV chunk');
    }
    fail('RTTY_E_WAV_FORMAT', 'WAV needs fmt and data chunks') unless $format && $data;
    return ($format, $data);
}

sub _format {
    my ($format, $data) = @_;
    my ($encoding, $channels, $rate, $byte_rate, $align, $bits) = @{$format};
    fail('RTTY_E_WAV_FORMAT', 'Only mono/stereo PCM 8/16/24 is supported')
        unless $encoding == 1
        && ($channels == 1 || $channels == 2)
        && ($bits == 8 || $bits == 16 || $bits == 24);
    fail('RTTY_E_WAV_FORMAT', 'Invalid rate or block alignment')
        if $rate < 1000
        || $rate > 384000
        || $align != $channels * $bits / 8
        || $byte_rate != $rate * $align
        || $data->[1] % $align != 0;
    return ($channels, $rate, $align, $bits);
}

sub _decode_pcm {
    my ($raw, $bits, $channels, $policy) = @_;
    my @values;
    if ($bits == 8) {
        @values = map { ($_ - 128) / 128 } unpack('C*', $raw);
    }
    elsif ($bits == 16) {
        @values = map { $_ / 32768 } unpack('s<*', $raw);
    }
    else {
        for (my $i = 0; $i < length $raw; $i += 3) {
            my $v = unpack('V', substr($raw, $i, 3) . "\0");
            $v -= 16777216 if $v >= 8388608;
            push @values, $v / 8388608;
        }
    }
    if ($channels == 2) {
        my @mono;
        for (my $i = 0; $i < @values; $i += 2) {
            push @mono,
                  $policy eq 'left'  ? $values[$i]
                : $policy eq 'right' ? $values[$i + 1]
                :                      ($values[$i] + $values[$i + 1]) / 2;
        }
        return \@mono;
    }
    return \@values;
}

sub read_file {
    my ($self, $path) = @_;
    return with_file($path, 'read', sub { $self->read($_[0]) });
}

sub write_file {
    my ($self, $path, $values, @pairs) = @_;
    my %args      = named_arguments(@pairs);
    my $overwrite = integer('overwrite', delete($args{overwrite}) // 0, 0, 1);
    return with_file($path, 'write', sub { $self->write($_[0], $values, %args) }, $overwrite);
}

sub write_blocks {
    my ($self, $path, $next, @pairs) = @_;
    fail('RTTY_E_ARGUMENT', 'Sample source must be a code reference') unless ref($next) eq 'CODE';
    my %args      = named_arguments(@pairs);
    my $overwrite = integer('overwrite', delete($args{overwrite}) // 0, 0, 1);
    return with_file(
        $path, 'write',
        sub {
            my $writer = $self->writer($_[0], %args);
            while (defined(my $block = $next->())) { $writer->feed($block) }
            return $writer->finish;
        },
        $overwrite
    );
}

sub read_blocks {
    my ($self, $path, $callback) = @_;
    fail('RTTY_E_ARGUMENT', 'Block callback must be a code reference')
        unless ref($callback) eq 'CODE';
    return with_file(
        $path, 'read',
        sub {
            my $reader = $self->reader($_[0]);
            my %metadata =
                map { ($_ => $reader->{$_}) } qw(sample_rate bits channels sample_count warnings);
            while (my $block = $reader->{next}->()) {
                $callback->(
                    $block,
                    {
                        %metadata, warnings => [map { +{%{$_}} } @{$metadata{warnings}}]
                    }
                );
            }
            return \%metadata;
        }
    );
}

sub reader {
    my ($self, $fh) = @_;
    fail('RTTY_E_ARGUMENT', 'An open file handle is required') unless openhandle($fh);
    binmode($fh)    or fail('RTTY_E_IO', 'Cannot set binary mode');
    seek($fh, 0, 2) or fail('RTTY_E_IO', 'A seekable WAV handle is required');
    my $size = tell($fh);
    fail('RTTY_E_RESOURCE', 'WAV exceeds max_bytes') if $size > $self->{max_bytes};
    seek($fh, 0, 0) or fail('RTTY_E_IO', 'Cannot rewind WAV handle');
    my ($riff, $length, $wave) = unpack('a4Va4', read_exact($fh, 12));
    fail('RTTY_E_WAV_FORMAT',    'Expected RIFF/WAVE') unless $riff eq 'RIFF' && $wave eq 'WAVE';
    fail('RTTY_E_WAV_TRUNCATED', 'RIFF size exceeds available bytes') if $length + 8 > $size;
    fail('RTTY_E_WAV_FORMAT',    'RIFF size is inconsistent')         if $length < 4;
    my @warnings =
        $length + 8 < $size
        ? ({code => 'RTTY_W_WAV_TRAILING', message => 'Ignored bytes after RIFF boundary'})
        : ();
    my ($format, $data) = _chunks($fh, $length + 8);
    my ($channels, $rate, $align, $bits) = _format($format, $data);
    seek($fh, $data->[0], 0) or fail('RTTY_E_IO', 'Cannot seek to WAV data');
    my $remaining = $data->[1];
    my $next      = sub {
        return unless $remaining;
        my $count = $self->{block_samples} * $align;
        $count = $remaining if $count > $remaining;
        my $raw = read_exact($fh, $count);
        $remaining -= $count;
        return Ham::RTTY::_Internal::PDL::decode_pcm($raw, $bits, $channels, $self->{stereo})
            if $self->{backend} eq 'pdl';
        return _decode_pcm($raw, $bits, $channels, $self->{stereo});
    };
    return {
        sample_rate  => $rate,
        bits         => $bits,
        channels     => $channels,
        sample_count => $data->[1] / $align,
        warnings     => \@warnings,
        next         => $next
    };
}

sub read {    ## no critic (Subroutines::ProhibitBuiltinHomonyms)
    my ($self, $fh) = @_;
    my $reader = $self->reader($fh);
    my @out;
    while (my $block = $reader->{next}->()) { push @out, @{$block} }
    return {
        sample_rate => $reader->{sample_rate},
        bits        => $reader->{bits},
        channels    => $reader->{channels},
        warnings    => $reader->{warnings},
        samples     => \@out
    };
}

sub writer {
    my ($self, $fh, @pairs) = @_;
    my %args = named_arguments(@pairs);
    options(\%args, qw(sample_rate sample_count bits));
    my $rate = integer('sample_rate', $args{sample_rate} // 16000, 1000, 384000);
    my $bits = integer('bits',        $args{bits}        // 16,    8,    24);
    fail('RTTY_E_ARGUMENT', 'bits must be 8, 16 or 24')
        unless $bits == 8 || $bits == 16 || $bits == 24;
    my $count = integer('sample_count', $args{sample_count}, 0, 4294967295);
    my $bytes = $count * $bits / 8;
    fail('RTTY_E_RESOURCE', 'WAV exceeds configured or RIFF limit')
        if $bytes + 44 + $bytes % 2 > $self->{max_bytes} || $bytes + 36 + $bytes % 2 > 4294967295;
    fail('RTTY_E_ARGUMENT', 'An open file handle is required') unless openhandle($fh);
    binmode($fh) or fail('RTTY_E_IO', 'Cannot set binary mode');
    write_bytes(
        $fh,
        pack(
            'a4Va4a4VvvVVvva4V',
            'RIFF',    36 + $bytes + $bytes % 2,
            'WAVE',    'fmt ', 16,     1, 1, $rate, $rate * $bits / 8,
            $bits / 8, $bits,  'data', $bytes
        )
    );
    return bless {
        fh      => $fh,
        backend => $self->{backend},
        bits    => $bits,
        count   => $count,
        written => 0,
        state   => 'READY',
        bytes   => $bytes
        },
        'Ham::RTTY::_Internal::WavWriter';
}

sub write {    ## no critic (Subroutines::ProhibitBuiltinHomonyms)
    my ($self, $fh, $values, @pairs) = @_;
    my %args = named_arguments(@pairs);
    samples($values, 100000000);
    my $writer = $self->writer($fh, %args, sample_count => scalar @{$values});
    for (my $i = 0; $i < @{$values}; $i += 4096) {
        my $end = $i + 4095;
        $end = $#{$values} if $end > $#{$values};
        $writer->feed([@{$values}[$i .. $end]]);
    }
    return $writer->finish;
}

1;

=encoding UTF-8

=head1 NAME

Ham::RTTY::Audio - read and write bounded PCM WAV samples

=head1 SYNOPSIS

    use strict;
    use warnings;
    use Ham::RTTY;
    use Ham::RTTY::Audio;

    my $cw = Ham::RTTY->new(sample_rate => 8000, frequency => 650);
    my $audio = Ham::RTTY::Audio->new;
    $audio->write_file('raw-demo.wav', $cw->samples('SOS'),
        sample_rate => 8000);
    my $recording = $audio->read_file('raw-demo.wav');
    print scalar(@{$recording->{samples}}), " samples\n";

The destination must be new, or use C<overwrite =E<gt> 1> explicitly.
No Morse decoding or sound playback occurs in this class.

=head1 FORMATS

Input is seekable RIFF/WAVE with PCM encoding 1: unsigned 8-bit or signed
little-endian 16/24-bit, one or two channels, and integer rate 1000..384000 Hz.
Output is mono PCM at a supported bit depth. Sample arrays contain finite
normalized values in [-1,1]; raw WAV bytes are a separate binary format.

Stereo C<left>/C<right> selects one channel. C<mix> averages both; this can
cancel opposite-phase audio. Reading always returns mono samples, while the
metadata C<channels> field records the original number of channels.

Unknown chunks and odd-byte chunk padding are skipped. Duplicate fmt/data
chunks, compressed/float/extensible WAV, RF64, WAVE64 and inconsistent sizes
are rejected. Streaming placeholder RIFF lengths are not supported. A complete
WAV with an empty data chunk is legal. Extra bytes outside the RIFF boundary
are ignored with C<RTTY_W_WAV_TRAILING> in metadata; file size limits include
them. Reading rewinds the handle to file offset zero.

=head1 METHODS

=head2 new

    my $audio = Ham::RTTY::Audio->new(%options);

Returns an Audio helper. Options:

=over 4

=item * C<max_bytes>: 64000000; integer 44..4294967295. Bounds input file size or complete output including header and padding.

=item * C<block_samples>: 4096; integer 1..1000000. Number of mono sample frames per reader block, before/after stereo selection.

=item * C<stereo>: C<mix> (default), C<left> or C<right>.

=item * C<backend>: C<perl> (default), C<pdl> or C<auto>. See L<Ham::RTTY/OPTIONAL PDL BACKEND>.

=back

Undefined optional values use defaults. Unknown/duplicate options or invalid
values raise C<RTTY_E_ARGUMENT>. The input rate is read from the WAV header;
the output rate is supplied to a writing method.

=head2 read_file

    my $recording = $audio->read_file($path);

Opens, reads and closes a WAV path. Returns the same collecting hash as
L</read>. The full sample array is retained; use L</read_blocks> for large
files. The input is preserved on processing failure.

=head2 read_blocks

    my $metadata = $audio->read_blocks($path, sub {
        my ($samples, $info) = @_;
        # Process this block; $info describes the original recording.
    });

Opens a WAV, invokes the callback once per nonempty normalized mono block,
closes input and returns metadata. Empty data means no callback invocations.
Callback exceptions propagate after handle closure. The callback must be a
code reference and its return value is ignored. Each metadata argument is a
fresh copy with C<sample_rate>, C<bits>, C<channels>, C<sample_count> and
C<warnings>. The sample count is the total original mono/stereo frame count,
not the current block length. Reader block size is C<block_samples>.

=head2 reader

    my $reader = $audio->reader($handle);
    while (my $samples = $reader->{next}->()) {
        # Consume the next normalized mono block.
    }

Requires an open readable, seekable handle holding a complete WAV. Validates
RIFF/chunk structure, selects the data region and returns an unblessed hash
with C<sample_rate>, C<bits>, C<channels>, C<sample_count>, C<warnings> and
C<next>. C<next> is a code reference yielding arrays, then C<undef> at EOF.
It reads samples only as requested. Do not reposition or close the handle
until finished; the library does not close caller-owned handles.

=head2 read

    my $recording = $audio->read($handle);

Collects L</reader> into a hash with C<sample_rate>, C<bits>, C<channels>,
C<warnings> and C<samples>. It does not include C<next> or C<sample_count>;
use the array length for the collected count. The caller still owns the
handle. Perl arrays can use much more memory than the WAV byte length.

=head2 write_file

    my $stats = $audio->write_file($path, $samples,
        sample_rate => 8000, bits => 16, overwrite => 0);

Opens, writes and closes a mono WAV. Accepts L</write> options and
C<overwrite> (integer 0 or 1; default 0). Returns writer statistics. Existing
paths are protected by default; see L<Ham::RTTY/FILE OWNERSHIP AND REPLACEMENT>
for replacement, permissions and cleanup behavior.

=head2 write_blocks

    my $stats = $audio->write_blocks($path, $next,
        sample_rate => 8000, sample_count => $total_count, bits => 16);

Requires a code reference returning sample arrays and C<undef> at EOF.
Accepts L</writer> options plus C<overwrite>. The exact total count is required
for the header; streaming does not allow an unknown-length WAV. Empty blocks
are accepted and the source must eventually return C<undef>. Too few or too
many samples are errors. Owns and closes the output handle, returning writer
statistics. Callback/processing failure attempts output cleanup using the
same rules as C<write_file>.

=head2 write

    my $stats = $audio->write($handle, $samples,
        sample_rate => 8000, bits => 16);

Collecting convenience writer. The supplied array is validated and limited
to 100000000 samples, then written in blocks of at most 4096. Sample count is
derived from the array; do not supply C<sample_count>. Options are
C<sample_rate> (16000 by default; integer 1000..384000) and C<bits>
(8, 16 or 24; default 16). Returns writer statistics. The output handle must
be open for binary writing and remains owned by the caller.

=head2 writer

    my $writer = $audio->writer($handle,
        sample_rate => 8000, sample_count => $total_count, bits => 16);

Writes the header immediately and returns an internal writer object with the
public operations below. C<sample_count> is required (integer 0..4294967295).
Rate and bit-depth options match L</write>. Both C<max_bytes> and RIFF size
limits apply before header output. An output handle need not seek because
the total count is known. Keep it open and close it yourself after finish.

=head1 WRITER OPERATIONS

The concrete writer package is internal; obtain it through L</writer>.
The following methods form its returned-object interface.

=head2 feed

    $writer->feed($samples);

Writes a block of at most 1000000 normalized mono samples and returns the
writer. Count must not exceed the declared total. Invalid input preserves
state/counters. Successful feeds set C<ACTIVE>. Quantization rounds to nearest
integer, with halves away from zero; +1 clips to the largest positive PCM
integer, while -1 maps to negative full scale (0 for unsigned 8-bit storage).

=head2 result

    my $stats = $writer->result;

Returns a fresh C<< {state => ..., samples => $written_count} >> hash.
The count excludes header and padding bytes.

=head2 finish

    my $stats = $writer->finish;

Requires the exact declared sample count, writes any required final padding,
sets C<FINISHED> and returns statistics. It is idempotent. If the count is too
small, C<RTTY_E_ARGUMENT> is thrown and missing samples can still be fed.

=head2 state

    my $state = $writer->state;

Returns C<READY>, C<ACTIVE>, C<FINISHED> or C<FAILED>. I/O failure sets FAILED;
after that, discard the writer and partial output. It has no reset operation.
Feed after finish/failure raises C<RTTY_E_STATE>.

=head1 ERRORS

Invalid options/sample values/counts raise C<RTTY_E_ARGUMENT>; unsupported
formats raise C<RTTY_E_WAV_FORMAT>; incomplete declared data raises
C<RTTY_E_WAV_TRUNCATED>; size limits raise C<RTTY_E_RESOURCE>; handle failures
raise C<RTTY_E_IO>. Input and output handles supplied directly are never closed
by this class. A failed direct write can leave partial output.

=head1 SEE ALSO

L<Ham::RTTY> for text-to-WAV and WAV decoding, L<Ham::RTTY::Generator> for sample
generation, L<Ham::RTTY::Result/WARNINGS> for the trailing-byte warning.

=head1 AUTHOR

Giacomo Picchiarelli

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2026 Giacomo Picchiarelli.
Artistic License 2.0. See F<LICENSE> in the source distribution.

=cut
