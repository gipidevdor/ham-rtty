#!/usr/bin/env perl
use 5.020;
use strict;
use warnings;
use Getopt::Long qw(GetOptions);
use Ham::RTTY;
my (%args, $help);
GetOptions(
    'shift=f'       => \$args{shift},
    'stop-bits=f'   => \$args{stop_bits},
    'variant=s'     => \$args{variant},
    'usos=i'        => \$args{usos},
    'baud=f'        => \$args{baud},
    'reverse!'      => \$args{reverse},
    'mark=f'        => \$args{mark},
    'sample-rate=i' => \$args{sample_rate},
    'amplitude=f'   => \$args{amplitude},
    'backend=s'     => \$args{backend},
    'bits=i'        => \$args{bits},
    'max-bytes=i'   => \$args{max_bytes},
    'max-samples=i' => \$args{max_samples},
    'block-size=i'  => \$args{block_size},
    'lenient!'      => \$args{lenient},
    'overwrite!'    => \$args{overwrite},
    'help|h'        => \$help
) or die "Invalid sender options; use --help\n";
if ($help) {
    print <<'HELP';
Usage: perl -Ilib examples/send.pl [OPTIONS] FILE TEXT ...

Create a mono WAV practice recording.

Example:
  perl -Ilib examples/send.pl --baud 50 practice.wav "CQ TEST"

Timing and tone:
  --baud N               Bit rate (default: 45.45).
  --stop-bits N          Stop duration: 1, 1.5 (default) or 2.
  --variant NAME         ita2 (default) or us.
  --usos 0|1             Unshift on space (default: 1).
  --mark HZ              MARK tone (default: 2125).
  --shift HZ             SPACE minus MARK (default: 170).
  --reverse              Swap MARK and SPACE tones.

WAV format and amplitude:
  --sample-rate HZ       Samples/second (default: 16000).
  --bits 8|16|24         PCM bits per sample (default: 16).
  --amplitude N          Peak amplitude, 0..1 (default: 0.8).

Processing and limits:
  --backend NAME         perl|pdl|auto (default: perl).
  --block-size N         Samples per output block (default: 4096).
  --max-samples N        Sample ceiling (default: 10000000).
  --max-bytes BYTES      File byte ceiling (default: 64000000).
  --lenient              Substitute unsupported symbols with ?.

Files are protected by default. Use --overwrite to replace FILE.
Quote text containing shell metacharacters, such as "CQ?". Use -h or --help for help.
HELP
    exit 0;
}
my ($path, @words) = @ARGV;
die "Usage: perl examples/send.pl [options] output.wav TEXT\n" unless defined($path) && @words;
%args = map { defined($args{$_}) ? ($_ => $args{$_}) : () } keys %args;
Ham::RTTY->new->write_wav(join(' ', @words), $path, %args);
