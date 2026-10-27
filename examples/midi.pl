#!/usr/bin/env perl
use 5.020;
use strict;
use warnings;
use Getopt::Long qw(GetOptions);
use Ham::RTTY;
my (%args, $help);
GetOptions(
    'wpm=f'           => \$args{wpm},
    'effective-wpm=f' => \$args{effective_wpm},
    'note=i'          => \$args{note},
    'velocity=i'      => \$args{velocity},
    'channel=i'       => \$args{channel},
    'program=i'       => \$args{program},
    'bpm=f'           => \$args{bpm},
    'ppqn=i'          => \$args{ppqn},
    'max-bytes=i'     => \$args{max_bytes},
    'unknown=s'       => \$args{unknown},
    'overwrite!'      => \$args{overwrite},
    'help|h'          => \$help
) or die "Invalid MIDI options; use --help\n";
if ($help) {
    print <<'HELP';
Usage: perl -Ilib examples/midi.pl [OPTIONS] FILE TEXT ...

Create a standard MIDI practice file.

Example:
  perl -Ilib examples/midi.pl --wpm 20 practice.mid "CQ TEST"

Morse timing:
  --wpm WPM              Character speed (default: 20).
  --effective-wpm WPM    Extended spacing speed (default: character speed).

Instrument and MIDI timing:
  --note N               Note, 0..127 (default: 77).
  --velocity N           Velocity, 1..127 (default: 100).
  --channel N            Channel, 1..16 (default: 1).
  --program N            Zero-based program, 0..127 (default: 80).
  --bpm N                MIDI tempo, 4..1000 (default: 120).
  --ppqn N               Ticks per quarter note, 1..32767 (default: 480).

Text and limits:
  --unknown error|skip   Unsupported symbols (default: error).
  --max-bytes BYTES      File byte ceiling (default: 8000000).

WPM controls Morse speed. BPM controls how MIDI ticks represent that timing.
Files are protected by default. Use --overwrite to replace FILE.
Use -h or --help for help. Playback requires a separate MIDI player.
HELP
    exit 0;
}
my ($path, @words) = @ARGV;
die "Usage: perl examples/midi.pl [options] output.mid TEXT\n" unless defined($path) && @words;
%args = map { defined($args{$_}) ? ($_ => $args{$_}) : () } keys %args;
Ham::RTTY->new->write_midi(join(' ', @words), $path, %args);
