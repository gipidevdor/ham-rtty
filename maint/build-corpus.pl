#!/usr/bin/env perl
use 5.020;
use strict;
use warnings;
use FindBin qw($Bin);
use File::Spec;

# Fixed reference schedule; this builder does not load Ham::RTTY.
my @runs = (
    [0, 3], [1, 1], [0, 1], [1, 1], [0, 1], [1, 1], [0, 3], [1, 3], [0, 1], [1, 3],
    [0, 1], [1, 3], [0, 3], [1, 1], [0, 1], [1, 1], [0, 1], [1, 1], [0, 3],
);
my $rate = 8000;
my $pi   = 4 * atan2(1, 1);
my ($pcm, $index) = ('', 0);
for my $run (@runs) {
    for (1 .. $run->[1] * 480) {
        my $value     = $run->[0] ? 0.6 * 32767 * sin(2 * $pi * 650 * $index / $rate) : 0;
        my $quantized = int($value >= 0 ? $value + 0.5 : $value - 0.5);
        $pcm .= pack('s<', $quantized);
        ++$index;
    }
}
my $output = File::Spec->catfile($Bin, '..', 'corpus', 'sos-650hz-20wpm.wav');
open my $fh, '>:raw', $output or die "Cannot open $output: $!\n";
print {$fh} pack(
    'a4Va4a4VvvVVvva4V',
    'RIFF', 36 + length($pcm),
    'WAVE', 'fmt ', 16, 1, 1, $rate, $rate * 2, 2, 16, 'data', length($pcm)
    ),
    $pcm
    or die "Cannot write $output: $!\n";
close $fh or die "Cannot close $output: $!\n";
