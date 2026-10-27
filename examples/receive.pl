#!/usr/bin/env perl
use 5.020;
use strict;
use warnings;
use Carp         qw(croak);
use Getopt::Long qw(GetOptions);
use JSON::PP;
use Ham::RTTY;

my (%options, $json, $help, $all);
GetOptions(
    'frequency=f'        => \$options{frequency},
    'wpm=f'              => \$options{wpm},
    'effective-wpm=f'    => \$options{effective_wpm},
    'backend=s'          => \$options{backend},
    'stereo=s'           => \$options{stereo},
    'max-frames=i'       => \$options{max_frames},
    'min-frequency=f'    => \$options{min_frequency},
    'max-frequency=f'    => \$options{max_frequency},
    'frequency-step=f'   => \$options{frequency_step},
    'min-contrast=f'     => \$options{min_contrast},
    'filter-bandwidth=f' => \$options{filter_bandwidth},
    'min-snr-db=f'       => \$options{min_snr_db},
    'mark-snr-db=f'      => \$options{mark_snr_db},
    'all-stations'       => \$all,
    'min-purity=f'       => \$options{min_purity},
    'max-bytes=i'        => \$options{max_bytes},
    'block-samples=i'    => \$options{block_samples},
    'json!'              => \$json,
    'help|h'             => \$help,
) or die "Invalid receiver options; use --help\n";

if ($help) {
    print <<'HELP';
Usage: perl -Ilib examples/receive.pl [OPTIONS] FILE

Read a PCM WAV recording and print recovered text.

Example:
  perl -Ilib examples/receive.pl --frequency 700 --wpm 20 practice.wav

Results and hints:
  --json                  Include warnings and diagnostics in JSON.
  --all-stations          Return up to eight distinct keyed tones.
  --frequency HZ          Known tone (default: searched).
  --wpm WPM               Known character speed (default: estimated).
  --effective-wpm WPM     Known Farnsworth spacing speed.

Processing:
  --backend NAME          perl|pdl|auto (default: perl).
  --stereo NAME           mix|left|right (default: mix).
  --block-samples N       Samples per input block (default: 4096).

Tone search and detection:
  --min-frequency HZ      Search lower bound (default: 300).
  --max-frequency HZ      Search upper bound (default: 1500, below Nyquist).
  --frequency-step HZ     Candidate spacing (default: 50).
  --filter-bandwidth HZ   Per-section width (default: 180, or max(40,4*WPM)).
  --min-snr-db DB         Acquisition tone/guard threshold (default: 12).
  --mark-snr-db DB        Mark/local-noise threshold (default: 10).
  --min-contrast N        Envelope contrast, 0.01..1 (default: 0.60).
  --min-purity N          Spectral purity, 0.01..1 (default: 0.20).

Limits:
  --max-frames N          Retained 5 ms frames (default: 24000).
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
my $method  = $all ? 'read_wav_channels' : 'read_wav';
my $result  = Ham::RTTY->new->$method($ARGV[0], %options);
my @results = $all ? @{$result} : ($result);
if ($json) {
    print JSON::PP->new->utf8->canonical->pretty->encode(
        $all ? [map { $_->as_hash } @results] : $result->as_hash);
}
else {
    binmode STDOUT, ':encoding(UTF-8)' or croak $!;
    for my $station (@results) {
        print($all ? $station->frequency . " Hz: " : '', $station->text, "\n");
        for my $warning (@{$station->warnings}) {
            warn "$warning->{code}: $warning->{message}\n";
        }
    }
}
exit((grep { $_->has_text } @results) ? 0 : 1);
