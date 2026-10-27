use 5.020;
use strict;
use warnings FATAL => 'all';
use Test::More;
use Ham::RTTY::Baudot;
use Ham::RTTY::Encoder;

# Independent numeric transcription of ITU-T S.1 (03/93), Table 1.
# S.1 elements 1..5 are transmitted first-to-last; here bit 1 is the LSB.
my @letters = split //, 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
my @codes   = (
    3,  25, 14, 9,  1, 13, 26, 20, 6,  11, 15, 18, 28, 12,
    24, 22, 23, 10, 5, 16, 7,  30, 19, 29, 21, 17
);
my @figures = (
    '-', '?', ':', "\x05", '3', undef, undef, undef, '8', "\a",
    '(', ')', '.', ',',    '9', '0',   '1',   '4',   "'", '5',
    '7', '=', '2', '/',    '6', '+'
);
my $table   = Ham::RTTY::Baudot->new->tables;
my $encoder = Ham::RTTY::Encoder->new;
for my $i (0 .. 25) {
    is($table->{letters}[$codes[$i]], $letters[$i], "S.1 letter $letters[$i]");
    is($table->{figures}[$codes[$i]], $figures[$i], "S.1 figure position $letters[$i]");
    is($encoder->frames($letters[$i])->[1]{code},
        $codes[$i], 'encoder matches independent numeric vector');
}
for my $control ([0, "\0"], [2, "\n"], [4, ' '], [8, "\r"]) {
    is($table->{letters}[$control->[0]], $control->[1], 'common control in letters');
    is($table->{figures}[$control->[0]], $control->[1], 'common control in figures');
}
for my $baud (20, 45.45, 50, 56.25, 75, 100, 110, 300) {
    my $events =
        Ham::RTTY::Encoder->new(baud => $baud, leading_idle => 0, trailing_idle => 0)->events('A');
    my $total = 0;
    $total += $_->{duration} for @{$events->{segments}};
    cmp_ok(abs($total / 1000000 - 15 / $baud), '<=', 1e-6, "two 7.5-bit frames at $baud baud");
}
my $us = Ham::RTTY::Baudot->new(variant => 'us')->tables;
for my $position ([9, '$'], [13, '!'], [26, '&'], [20, '#'], [11, "'"], [5, "\a"], [30, ';'],
    [17, '"'])
{
    is($us->{figures}[$position->[0]], $position->[1], 'US national profile difference');
}
done_testing;
