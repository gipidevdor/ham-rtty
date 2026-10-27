package Ham::RTTY::MIDI;
use 5.020;
use strict;
use warnings;
use Scalar::Util                   qw(openhandle);
use Ham::RTTY::Events              qw(validate_events);
use Ham::RTTY::_Internal::IO       qw(write_bytes with_file);
use Ham::RTTY::_Internal::Validate qw(fail integer number options named_arguments);
our $VERSION = '0.01';

sub new {
    my ($class, @pairs) = @_;
    my %args = named_arguments(@pairs);
    options(\%args, qw(mark_note space_note velocity channel program bpm ppqn max_bytes));
    return bless {
        mark_note  => integer('mark_note',  $args{mark_note}  // 77,  0, 127),
        space_note => integer('space_note', $args{space_note} // 79,  0, 127),
        velocity   => integer('velocity',   $args{velocity}   // 100, 1, 127),
        channel    => integer('channel',    $args{channel}    // 1,   1, 16),
        program    => integer('program',    $args{program}    // 80,  0, 127),
        bpm        => number('bpm', $args{bpm} // 120, 4, 1000),
        ppqn       => integer('ppqn',      $args{ppqn}      // 480,     1,  32767),
        max_bytes  => integer('max_bytes', $args{max_bytes} // 8000000, 64, 64000000),
    }, $class;
}

sub _vlq {
    my ($value) = @_;
    fail('RTTY_E_TIMING', 'MIDI delta exceeds four-byte VLQ range') if $value > 0x0fff_ffff;
    my @bytes = ($value & 0x7f);
    while ($value >>= 7) { unshift @bytes, ($value & 0x7f) | 0x80 }
    return pack('C*', @bytes);
}

sub encode {
    my ($self, $events) = @_;
    my $field = validate_events($events);
    my $tempo = int(60_000_000 / $self->{bpm} + 0.5);

    # Keep the original event units until the final tick boundary.
    my $numerator   = $self->{ppqn} * ($field eq 'samples' ? 1_000_000 : 1);
    my $denominator = $tempo * ($field eq 'samples' ? $events->{sample_rate} : 1);
    my $channel     = $self->{channel} - 1;
    my $track =
          "\0\xff\x51\x03"
        . substr(pack('N', $tempo), 1, 3)
        . pack('CCC', 0, 0xc0 | $channel, $self->{program});
    my ($time, $last_tick) = (0, 0);

    for my $segment (@{$events->{segments}}) {
        my $start = int($time * $numerator / $denominator + 0.5);
        $time += $segment->{$field};
        my $note = $self->{$segment->{state} eq 'mark' ? 'mark_note' : 'space_note'};
        my $end  = int($time * $numerator / $denominator + 0.5);
        fail('RTTY_E_TIMING', 'MIDI resolution would produce a zero-length note') if $end <= $start;
        $track .=
            _vlq($start - $last_tick) . pack('CCC', 0x90 | $channel, $note, $self->{velocity});
        $track .= _vlq($end - $start) . pack('CCC', 0x80 | $channel, $note, 0);
        $last_tick = $end;
        fail('RTTY_E_RESOURCE', 'MIDI exceeds max_bytes')
            if length($track) + 30 > $self->{max_bytes};
    }
    $track .= _vlq(int($time * $numerator / $denominator + 0.5) - $last_tick) . "\xff\x2f\0";
    return pack('a4Nnnna4N', 'MThd', 6, 0, 1, $self->{ppqn}, 'MTrk', length $track) . $track;
}

sub write_file {
    my ($self, $path, $events, @pairs) = @_;
    my %args = named_arguments(@pairs);
    options(\%args, 'overwrite');
    my $overwrite = integer('overwrite', $args{overwrite} // 0, 0, 1);
    return with_file($path, 'write', sub { $self->write($_[0], $events) }, $overwrite);
}

sub write {    ## no critic (Subroutines::ProhibitBuiltinHomonyms)
    my ($self, $fh, $events) = @_;
    fail('RTTY_E_ARGUMENT', 'An open file handle is required') unless openhandle($fh);
    my $bytes = $self->encode($events);
    binmode($fh) or fail('RTTY_E_IO', 'Cannot set binary mode');
    write_bytes($fh, $bytes);
    return length $bytes;
}
1;

=encoding UTF-8

=head1 NAME

Ham::RTTY::MIDI - export keyed events to standard MIDI files

=head1 SYNOPSIS

    use strict;
    use warnings;
    use Ham::RTTY::Encoder;
    use Ham::RTTY::MIDI;

    my $events = Ham::RTTY::Encoder->new(baud => 50)->events('SOS');
    my $midi = Ham::RTTY::MIDI->new(mark_note => 77, space_note => 79, program => 80);
    my $bytes = $midi->encode($events);
    print length($bytes), " MIDI bytes\n";

To save instead, call C<< $midi->write_file('midi-demo.mid', $events) >>.
The path must be new unless C<overwrite =E<gt> 1> is explicitly selected.

=head1 DESCRIPTION

Exports one MARK or SPACE note at a time in Standard MIDI File (SMF) type 0 format,
with one track, tempo, program change, note-on/off and end-of-track events.
It does not render sound or send events to a MIDI device. No external MIDI
module is required. To start with ordinary text, use L<Ham::RTTY/write_midi>.

=head1 METHODS

=head2 new

    my $midi = Ham::RTTY::MIDI->new(%options);

Options and inclusive ranges:

=over 4

=item * C<mark_note>: 77; C<space_note>: 79; integer 0..127.

=item * C<velocity>: 100; integer 1..127, used for note-on events.

=item * C<channel>: 1; integer 1..16. Public channels are one-based.

=item * C<program>: 80; integer 0..127. Program numbers are zero-based.

=item * C<bpm>: 120; finite number 4..1000, controlling the encoded tempo.

=item * C<ppqn>: 480; integer 1..32767, pulses (ticks) per quarter note.

=item * C<max_bytes>: 8000000; integer 64..64000000, bounding encoded output.

=back

Undefined optional values use defaults. Unknown/duplicate names or invalid
ranges raise C<RTTY_E_ARGUMENT>. Note and program are independent of the audio
frequency setting in Ham::RTTY. Under standard A440 tuning note 77 is about
698.46 Hz; General MIDI program 80 denotes a square lead. A player may use
other sounds or tuning. Channel 10 is normally percussion; choose a melodic
channel when a sustained pitch is desired.

=head2 encode

    my $bytes = $midi->encode($events);

Validates TimedEvents or SampledEvents and returns a complete binary SMF
scalar. Leading/trailing silence is preserved. MARK and SPACE runs become two configurable notes. This is a visual/debug rendering. Source event durations determine real-time RTTY
speed. Changing BPM changes tick mapping, not the requested source timing.
Playback sound and envelopes depend on the player/synthesizer.

Cumulative event boundaries round to nearest integer tick, with halves
upward, using the encoded integer-microsecond tempo. Sampled events retain
their original units until this boundary calculation. Round trips through
other resolutions may lose precision. A note rounding to zero ticks raises
C<RTTY_E_TIMING>; increase PPQN or lengthen events. Deltas exceeding the
four-byte SMF limit also raise that code. This operation collects the track
in memory and is bounded by C<max_bytes>.

=head2 write

    my $count = $midi->write($handle, $events);

Encodes/validates the whole file before writing binary bytes. Returns the
number of bytes written. The handle must be open for output, need not seek,
and remains owned by the caller. Check C<close> errors. An I/O failure can
leave partial output.

=head2 write_file

    my $count = $midi->write_file($path, $events, overwrite => 0);

Owns and closes the file; returns its byte count. The only additional option
is C<overwrite> (integer 0 or 1, default 0). Default output uses exclusive
creation. Explicit replacement uses a temporary sibling and rename, preserving
the old destination if generation fails. See
L<Ham::RTTY/FILE OWNERSHIP AND REPLACEMENT> for cleanup and replacement limits.

=head1 ERRORS

Invalid options/event shape raise C<RTTY_E_ARGUMENT>; invalid alternation or
tick resolution raises C<RTTY_E_TIMING>; event/file size limits raise
C<RTTY_E_RESOURCE>; file/handle failures raise C<RTTY_E_IO>. There is no
incremental object state or C<finish> method.

=head1 AUTHOR

Giacomo Picchiarelli

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2026 Giacomo Picchiarelli.
Artistic License 2.0. See F<LICENSE> in the source distribution.

=cut
