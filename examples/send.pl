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
    'frequency=f'     => \$args{frequency},
    'sample-rate=i'   => \$args{sample_rate},
    'amplitude=f'     => \$args{amplitude},
    'attack-ms=f'     => \$args{attack_ms},
    'release-ms=f'    => \$args{release_ms},
    'backend=s'       => \$args{backend},
    'bits=i'          => \$args{bits},
    'max-bytes=i'     => \$args{max_bytes},
    'max-samples=i'   => \$args{max_samples},
    'block-size=i'    => \$args{block_size},
    'unknown=s'       => \$args{unknown},
    'overwrite!'      => \$args{overwrite},
    'help|h'          => \$help
) or die "Invalid sender options; use --help\n";
if ($help) {
    print <<'HELP';
Usage: perl -Ilib examples/send.pl [OPTIONS] FILE TEXT ...

Create a mono WAV practice recording.

Example:
  perl -Ilib examples/send.pl --wpm 20 practice.wav "CQ TEST"

Timing and tone:
  --wpm WPM              Character speed (default: 20).
  --effective-wpm WPM    Extended spacing speed (default: character speed).
  --frequency HZ         Tone (default: 700).

WAV format and envelope:
  --sample-rate HZ       Samples/second (default: 16000).
  --bits 8|16|24         PCM bits per sample (default: 16).
  --amplitude N          Peak amplitude, 0..1 (default: 0.8).
  --attack-ms MS         Raised-cosine attack (default: 5).
  --release-ms MS        Raised-cosine release (default: 5).

Processing and limits:
  --backend NAME         perl|pdl|auto (default: perl).
  --block-size N         Samples per output block (default: 4096).
  --max-samples N        Sample ceiling (default: 10000000).
  --max-bytes BYTES      File byte ceiling (default: 64000000).
  --unknown error|skip   Unsupported symbols (default: error).

Files are protected by default. Use --overwrite to replace FILE.
Quote text containing prosigns, such as "CQ <AR>". Use -h or --help for help.
HELP
    exit 0;
}
my ($path, @words) = @ARGV;
die "Usage: perl examples/send.pl [options] output.wav TEXT\n" unless defined($path) && @words;
%args = map { defined($args{$_}) ? ($_ => $args{$_}) : () } keys %args;
Ham::RTTY->new->write_wav(join(' ', @words), $path, %args);
