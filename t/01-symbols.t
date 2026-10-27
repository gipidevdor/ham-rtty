use strict;
use warnings;
use utf8;
use Test::More;
use Ham::RTTY;
use Ham::RTTY::_Internal::Symbols qw(alphabet prosigns);
my $cw          = Ham::RTTY->new;
my @itu_written = (
    'A' .. 'Z',
    '0' .. '9',
    'É', '.', ',', ':', '?', q{'}, '-', '/', '(', ')', q{"}, '=', '+', '@', '×'
);
is_deeply(
    [sort keys %{alphabet()}],
    [sort @itu_written],
    'written repertoire is exactly the ITU whitelist'
);
is_deeply(
    [sort keys %{prosigns()}],
    [qw(AR AS BT CT HH SK SN)],
    'only mnemonic tokens for admitted ITU signals'
);

# Independent reference vectors, not the implementation's symbol table.
my @letters =
    qw(.- -... -.-. -.. . ..-. --. .... .. .--- -.- .-.. -- -. --- .--. --.- .-. ... - ..- ...- .-- -..- -.-- --..);
my @digits = qw(----- .---- ..--- ...-- ....- ..... -.... --... ---.. ----.);
for my $i (0 .. 25) {
    my $letter = chr(65 + $i);
    is($cw->encode(lc $letter),   $letters[$i], "encode $letter");
    is($cw->decode($letters[$i]), $letter,      "decode $letter");
}
for my $i (0 .. 9) {
    is($cw->encode("$i"),        $digits[$i], "encode $i");
    is($cw->decode($digits[$i]), "$i",        "decode $i");
}
my @punct = (
    ['.',  '.-.-.-'],
    [',',  '--..--'],
    [':',  '---...'],
    ['?',  '..--..'],
    [q{'}, '.----.'],
    ['-',  '-....-'],
    ['/',  '-..-.'],
    ['(',  '-.--.'],
    [')',  '-.--.-'],
    [q{"}, '.-..-.'],
    ['=',  '-...-'],
    ['+',  '.-.-.'],
    ['@',  '.--.-.'],
    ['É',  '..-..']
);
for my $pair (@punct) {
    is($cw->encode($pair->[0]), $pair->[1], 'encode punctuation');
    is($cw->decode($pair->[1]), $pair->[0], 'decode punctuation');
}
is(
    $cw->encode("  cq\tde\nTESTCALL  "),
    '-.-. --.- / -.. . / - . ... - -.-. .- .-.. .-..',
    'normalize whitespace'
);
is($cw->encode('AR'),    '.- .-.', 'letters stay separate');
is($cw->encode('<AR>'),  '.-.-.',  'explicit AR');
is($cw->decode('.-.-.'), '+',      'punctuation preferred');
is(Ham::RTTY::Decoder->new(prefer_prosigns => 1)->decode('.-.-.'),
    '<AR>', 'explicit ambiguity policy');
my %prosigns = (
    AR => '.-.-.',
    AS => '.-...',
    CT => '-.-.-',
    SK => '...-.-',
    HH => '........',
    SN => '...-.',
    BT => '-...-',
);
for my $name (sort keys %prosigns) { is($cw->encode("<$name>"), $prosigns{$name}, "prosign $name") }
is($cw->encode('×'),    '-..-', 'ITU multiplication uses the X signal');
is($cw->decode('-..-'), 'X',    'shared multiplication waveform decodes deterministically as X');
eval { $cw->decode('...---...') };
is(ref($@) ? $@->code : "$@",
    'RTTY_E_SYMBOL', 'uninterrupted SOS is outside the chosen recommendation');
is($cw->encode(''),                                          '',          'empty text');
is($cw->decode('  '),                                        '',          'empty Morse');
is(Ham::RTTY::Encoder->new(unknown => 'skip')->encode('A! B'), '.- / -...', 'explicit skip policy');

for my $bad (
    '!',    '&',    ';',    '_',     '$',   'ß', '<NOPE>', '<BK>',
    '<KN>', '<KA>', '<VE>', '<SOS>', '<AR', "e\x{301}"
    )
{
    eval { $cw->encode($bad) };
    isa_ok($@, 'Ham::RTTY::Error');
    is((ref($@) ? $@->code : "$@"), 'RTTY_E_SYMBOL', 'strict unknown');
}
for my $bad ('/ ...', '... /', '... // ---', '... x', '------') {
    eval { $cw->decode($bad) };
    is((ref($@) ? $@->code : "$@"), 'RTTY_E_SYMBOL', 'reject malformed Morse');
}
for my $text ('HELLO WORLD', 'CQ CQ DE TESTCALL', '0123456789', 'TEST (A/B)?') {
    is($cw->decode($cw->encode($text)), $text, 'text round trip');
}
done_testing;
