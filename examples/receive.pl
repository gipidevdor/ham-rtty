#!/usr/bin/env perl
use 5.020;
use strict;
use warnings;
use Carp         qw(croak);
use Getopt::Long qw(GetOptions);
use JSON::PP;
use Ham::RTTY;

my (%options, $json, $help);
GetOptions(
    'shift=f'          => \$options{shift},
    'reverse!'         => \$options{reverse},
    'variant=s'        => \$options{variant},
    'usos=i'           => \$options{usos},
    'atc=i'            => \$options{atc},
    'search!'          => \$options{search},
    'mark=f'           => \$options{mark},
    'baud=f'           => \$options{baud},
    'backend=s'        => \$options{backend},
    'stereo=s'         => \$options{stereo},
    'max-frames=i'     => \$options{max_frames},
    'min-frequency=f'  => \$options{min_frequency},
    'max-frequency=f'  => \$options{max_frequency},
    'frequency-step=f' => \$options{frequency_step},
    'max-bytes=i'      => \$options{max_bytes},
    'block-samples=i'  => \$options{block_samples},
    'json!'            => \$json,
    'help|h'           => \$help,
) or die "Invalid receiver options; use --help\n";

if ($help) {
    print <<'HELP';
Usage: perl -Ilib examples/receive.pl [OPTIONS] FILE

Read a PCM WAV recording and print recovered text.

Example:
  perl -Ilib examples/receive.pl --mark 2125 --baud 50 practice.wav

Results and hints:
  --json                  Include warnings and diagnostics in JSON.
  --mark HZ               MARK tone (default: 2125).
  --shift HZ              SPACE minus MARK (default: 170).
  --reverse               Swap MARK and SPACE tones.
  --baud N                Bit rate (default: 45.45).
  --variant NAME          ita2 (default) or us.
  --usos 0|1              Unshift on space (default: 1).
  --atc 0|1               Automatic threshold correction (default: 1).
  --search                Acquire a tone pair at the configured shift.

Processing:
  --backend NAME          perl|pdl|auto (default: perl).
  --stereo NAME           mix|left|right (default: mix).
  --block-samples N       Samples per input block (default: 4096).

Tone search and detection:
  --min-frequency HZ      Search lower bound (default: 300).
  --max-frequency HZ      Search upper bound (default: 3000 minus shift, below Nyquist).
  --frequency-step HZ     Candidate spacing (default: 10).

Limits:
  --max-frames N          Retained frames (default: 200000).
  --max-bytes BYTES       File byte ceiling (default: 64000000).

Read warnings even when text is present. JSON contains its own warnings;
plain-text warnings go to stderr. Exit status: 0 with text, 1 without text.
For strict warning handling, use ham-rtty receive --strict FILE.
Use -h or --help for help.
HELP
    exit 0;
}
die "Usage: perl examples/receive.pl [options] input.wav\n" unless @ARGV == 1;
%options = map { defined($options{$_}) ? ($_ => $options{$_}) : () } keys %options;
my $result = Ham::RTTY->new->read_wav($ARGV[0], %options);
if ($json) {
    print JSON::PP->new->utf8->canonical->pretty->encode($result->as_hash);
}
else {
    binmode STDOUT, ':encoding(UTF-8)' or croak $!;
    print $result->text, "\n";
    for my $warning (@{$result->warnings}) {
        warn "$warning->{code}: $warning->{message}\n";
    }
}
exit($result->has_text ? 0 : 1);
