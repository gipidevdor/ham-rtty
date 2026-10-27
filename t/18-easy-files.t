use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use File::Spec;
use Ham::RTTY;
use Scalar::Util qw(openhandle);
my $root  = tempdir(CLEANUP => 1);
my $cw    = Ham::RTTY->new(sample_rate => 8000, frequency => 650, wpm => 20);
my $wav   = File::Spec->catfile($root, 'message with spaces.wav');
my $midi  = File::Spec->catfile($root, 'message.mid');
my $stats = $cw->write_wav('SOS', $wav);
ok(-s $wav, 'write WAV by path');
is(ref $stats,                'HASH', 'WAV returns existing writer statistics');
is($cw->read_wav($wav)->text, 'SOS',  'read WAV with automatic reception');
is($cw->read_wav($wav, frequency => 650, wpm => 20)->text, 'SOS',    'explicit receive hints');
is($cw->write_midi('SOS', $midi),                          -s $midi, 'MIDI returns bytes written');
open my $in, '<:raw', $midi or die $!;
read $in, my $header, 4;
close $in or die $!;
is($header, 'MThd', 'write MIDI by path');
my $size = -s $wav;
eval { $cw->write_wav('TEST', $wav) };
is((ref($@) ? $@->code : "$@"), 'RTTY_E_IO', 'existing file rejected');
is(-s $wav,                     $size,     'existing file preserved');
is($cw->read_wav($wav)->text,   'SOS',     'existing content preserved');

for my $path (undef, '', [], "bad\0path") {
    eval { $cw->read_wav($path) };
    is((ref($@) ? $@->code : "$@"), 'RTTY_E_ARGUMENT', 'invalid input path');
    eval { $cw->write_wav('SOS', $path) };
    is((ref($@) ? $@->code : "$@"), 'RTTY_E_ARGUMENT', 'invalid output path');
}
my $missing = File::Spec->catfile($root, 'missing.wav');
eval { $cw->read_wav($missing) };
is((ref($@) ? $@->code            : "$@"),  'RTTY_E_IO', 'missing file structured error');
is((ref($@) ? $@->context->{path} : undef), $missing,  'I/O error includes path');
for my $method (qw(write_wav write_midi)) {
    my $bad = File::Spec->catfile($root, "$method.bad");
    eval { $cw->$method('!', $bad) };
    is((ref($@) ? $@->code : "$@"), 'RTTY_E_SYMBOL', "$method propagates symbol error");
    ok(!-e $bad, "$method removes unsuccessful output");
    eval { $cw->$method('SOS', $bad, typo => 1) };
    is((ref($@) ? $@->code : "$@"), 'RTTY_E_ARGUMENT', "$method rejects unknown option");
    ok(!-e $bad, "$method leaves no output on option error");
}
eval { $cw->read_wav($wav, typo => 1) };
is((ref($@) ? $@->code : "$@"), 'RTTY_E_ARGUMENT', 'reader delegates option validation');
my $reject = File::Spec->catfile($root, 'limited.wav');
eval { $cw->write_wav('SOS', $reject, max_bytes => 44) };
is((ref($@) ? $@->code : "$@"), 'RTTY_E_RESOURCE', 'resource error preserved');
ok(!-e $reject, 'resource failure cleans output');
my $empty = File::Spec->catfile($root, 'empty.wav');
$cw->write_wav('', $empty);
my $result = $cw->read_wav($empty);
is($result->text, '', 'empty text is distinct from I/O failure');
ok($result->has_warnings,               'convenient warnings predicate');
ok(!$result->has_text,                  'convenient text predicate');
ok($cw->read_wav($wav)->has_text,       'nonempty text predicate');
ok(!Ham::RTTY::Result->new->has_warnings, 'empty warnings predicate');

for my $case (["  CQ !", '!', 6], ["A <WRONG>", '<WRONG>', 3], ["A\x{2003}B", "\x{2003}", 2]) {
    eval { $cw->encode($case->[0]) };
    my $error = $@;
    isa_ok($error, 'Ham::RTTY::Error');
    next unless ref $error;
    is($error->code,                'RTTY_E_SYMBOL', 'symbol code preserved');
    is($error->context->{symbol},   $case->[1],    'error identifies symbol');
    is($error->context->{position}, $case->[2],    'error identifies character position');
    like($error->message, qr/character $case->[2]/, 'human-readable position');
}
is(
    Ham::RTTY->new(wpm => 50, frequency => 1000)->read_wav($wav)->text,
    'SOS',
    'generation settings are not implicit reception hints'
);
my $pcm24 = File::Spec->catfile($root, '24-bit.wav');
$cw->write_wav('SOS', $pcm24, bits => 24);
is($cw->read_wav($pcm24)->text, 'SOS', 'file methods forward bit depth');
{
    no warnings 'redefine';
    my $captured;
    my $failed = File::Spec->catfile($root, 'interrupted.wav');
    local *Ham::RTTY::generate_wav = sub {
        my ($self, $text, $handle) = @_;
        $captured = $handle;
        print {$handle} 'incomplete' or die $!;
        Ham::RTTY::Error->throw(code => 'RTTY_E_IO', message => 'Injected write failure');
    };
    eval { $cw->write_wav('SOS', $failed) };
    is((ref($@) ? $@->message : "$@"), 'Injected write failure', 'processing error preserved');
    ok(!openhandle($captured), 'failed writer closes owned handle');
    ok(!-e $failed,            'partially written file removed');
}
{
    no warnings 'redefine';
    my $captured;
    local *Ham::RTTY::decode_wav = sub {
        $captured = $_[1];
        Ham::RTTY::Error->throw(code => 'RTTY_E_WAV_FORMAT', message => 'Injected read failure');
    };
    eval { $cw->read_wav($wav) };
    is((ref($@) ? $@->code : "$@"), 'RTTY_E_WAV_FORMAT', 'read error preserved');
    ok(!openhandle($captured), 'failed reader closes owned handle');
    ok(-s $wav,                'failed reader preserves input');
}
done_testing;
