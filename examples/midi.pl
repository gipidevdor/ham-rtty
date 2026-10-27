#!/usr/bin/env perl
use 5.020;
use strict;
use warnings;
use Getopt::Long qw(GetOptions);
use Ham::RTTY;
my (%args, $help);
GetOptions(
    'stop-bits=f'  => \$args{stop_bits},
    'variant=s'    => \$args{variant},
    'usos=i'       => \$args{usos},
    'baud=f'       => \$args{baud},
    'space-note=i' => \$args{space_note},
    'mark-note=i'  => \$args{mark_note},
    'velocity=i'   => \$args{velocity},
    'channel=i'    => \$args{channel},
    'program=i'    => \$args{program},
    'bpm=f'        => \$args{bpm},
    'ppqn=i'       => \$args{ppqn},
    'max-bytes=i'  => \$args{max_bytes},
    'lenient!'     => \$args{lenient},
    'overwrite!'   => \$args{overwrite},
    'help|h'       => \$help
) or die "Invalid MIDI options; use --help\n";
if ($help) {
    print <<'HELP';
Usage: perl -Ilib examples/midi.pl [OPTIONS] FILE TEXT ...

Create a standard MIDI practice file.

Example:
  perl -Ilib examples/midi.pl --baud 50 practice.mid "CQ TEST"

RTTY timing:
  --baud N               Bit rate (default: 45.45).
  --stop-bits N          Stop duration: 1, 1.5 (default) or 2.
  --variant NAME         ita2 (default) or us.
  --usos 0|1             Unshift on space (default: 1).

Instrument and MIDI timing:
  --mark-note N          MARK note, 0..127 (default: 77).
  --space-note N         SPACE note, 0..127 (default: 79).
  --velocity N           Velocity, 1..127 (default: 100).
  --channel N            Channel, 1..16 (default: 1).
  --program N            Zero-based program, 0..127 (default: 80).
  --bpm N                MIDI tempo, 4..1000 (default: 120).
  --ppqn N               Ticks per quarter note, 1..32767 (default: 480).

Text and limits:
  --lenient              Substitute unsupported symbols with ?.
  --max-bytes BYTES      File byte ceiling (default: 8000000).

Baud controls frame timing. BPM controls how MIDI ticks represent that timing.
Files are protected by default. Use --overwrite to replace FILE.
Use -h or --help for help. Playback requires a separate MIDI player.
HELP
    exit 0;
}
my ($path, @words) = @ARGV;
die "Usage: perl examples/midi.pl [options] output.mid TEXT\n" unless defined($path) && @words;
%args = map { defined($args{$_}) ? ($_ => $args{$_}) : () } keys %args;
Ham::RTTY->new->write_midi(join(' ', @words), $path, %args);
