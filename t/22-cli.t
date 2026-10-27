use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use File::Spec;
use Encode qw(encode);
use JSON::PP;
use Symbol qw(gensym);
use lib 't/lib';
use FaultHandle;
use Ham::RTTY;
use Ham::RTTY::_Internal::CLI;

sub cli {
    my ($arguments, $input, $fault) = @_;
    $input //= '';
    my ($stdout, $stderr) = ('', '');
    open my $in,  '<:raw', \$input  or die $!;
    open my $out, '>:raw', \$stdout or die $!;
    open my $err, '>:raw', \$stderr or die $!;
    my %handles = (in => $in, out => $out, err => $err);
    if ($fault) {
        for my $name (keys %{$fault}) {
            my $handle = gensym();
            tie *{$handle}, 'FaultHandle', bytes => $input, fail => $fault->{$name};
            $handles{$name} = $handle;
        }
    }
    my $status = Ham::RTTY::_Internal::CLI::run($arguments, @handles{qw(in out err)});
    close $_ or die $! for $in, $out, $err;
    return ($status, $stdout, $stderr);
}

sub file_bytes {
    my ($path) = @_;
    open my $in, '<:raw', $path or die $!;
    my $bytes = do { local $/; <$in> };
    close $in or die $!;
    return $bytes;
}
my ($status, $out, $err) = cli(['encode', 'CQ', 'TEST']);
is($status, 0,                         'encode succeeds');
is($out,    "-.-. --.- / - . ... -\n", 'independent text-to-Morse vector');
is($err,    '',                        'successful conversion has no diagnostics');
($status, $out) = cli(['decode', '--', '... --- ...']);
is($out, "SOS\n", 'independent Morse-to-text vector');
($status, $out) = cli(['decode', '--', '-.. .']);
is($out, "DE\n", 'end-of-options protects dash-leading Morse');
($status, $out) = cli(['decode', '--prefer-prosigns', '.-.-.']);
is($out, "<AR>\n", 'prosign preference is forwarded');
($status, $out) = cli(['encode'], "SOS\r\n");
is($out, "... --- ...\n", 'CRLF stdin is accepted');
($status, $out) = cli(['encode', '-i', '-'], "\xef\xbb\xbfSOS\n");
is($out, "... --- ...\n", 'UTF-8 BOM is accepted at start of input');
($status, $out) = cli(['decode'], "..-..\n");
is($out, encode('UTF-8', "\x{c9}\n"), 'decoded Unicode is UTF-8 bytes');
($status, $out) = cli(['encode', "\x{c3}\x{89}"]);
is($out, "..-..\n", 'UTF-8 positional argument is decoded');
my $wide = "\x{c9}";
utf8::upgrade($wide);
($status, $out) = cli(['encode', $wide]);
is($out, "..-..\n", 'already decoded argument is accepted');
($status, $out) = cli(['encode', '--unknown', 'skip', 'SOS!']);
is($out, "... --- ...\n", 'explicit skip policy is forwarded');
($status, $out) = cli(['encode']);
is($status, 0,    'empty text is a valid conversion');
is($out,    "\n", 'empty text has a terminating newline');
{
    local $ENV{POSIXLY_CORRECT} = 1;
    ($status, $out) = cli(['encode', 'SOS!', '--unknown', 'skip']);
    is($out, "... --- ...\n", 'option order is independent of POSIXLY_CORRECT');
}
for my $arguments (['--help'], ['-h'], ['help'],
    map { [$_, '--help'], ['help', $_] } qw(encode decode events wav midi receive))
{
    ($status, $out, $err) = cli($arguments, '', {in => {read => 1}});
    is($status, 0, 'help succeeds without reading input');
    like($out, qr/Usage: ham-rtty/, 'help identifies executable');
    is($err, '', 'help has no error output');
}
for my $command (qw(encode decode events wav midi receive)) {
    ($status, $out) = cli(['help', $command]);
    like($out, qr/Usage: ham-rtty \Q$command\E \[OPTIONS\]/, 'help starts with the selected task');
    like($out, qr/Example:\n  ham-rtty \Q$command\E /,       'help includes a task-specific example');
    unlike($out, qr/^Commands:/m, 'task help omits the unrelated command menu');
    ok(!(grep { length($_) > 78 } split /\n/, $out), 'task help fits a narrow terminal');
    unlike($out, qr/\t/, 'help alignment uses portable spaces');
}
($status, $out) = cli(['help', 'wav']);
like($out, qr/^Usage: .*--output FILE/m, 'WAV synopsis states the required destination');
like($out, qr/--frequency HZ/,           'tone option names its unit');
like($out, qr/Timing and tone:/,         'generation help groups timing controls');
($status, $out) = cli(['help', 'receive']);
like(
    $out,
    qr/Results:.*Tone search:.*Detection thresholds:.*Limits and buffering:/s,
    'receive help separates common results from advanced controls'
);
($status, $out, $err) = cli(['wav', '--typo']);
like($err, qr/Try: ham-rtty help wav\n\z/, 'usage failure leads to the relevant help');
($status, $out, $err) = cli(['missing']);
like($err, qr/Try: ham-rtty --help\n\z/, 'unknown command leads to command discovery');

for my $arguments (['--version'], ['encode', '--version']) {
    ($status, $out, $err) = cli($arguments);
    is($status, 0,                            'version succeeds');
    is($out,    "ham-rtty $Ham::RTTY::VERSION\n", 'version matches library');
}
for my $case (
    [[],                                                           2, 'RTTY_E_ARGUMENT'],
    [['missing'],                                                  2, 'RTTY_E_ARGUMENT'],
    [['--version', 'extra'],                                       2, 'RTTY_E_ARGUMENT'],
    [['help', 'missing'],                                          2, 'RTTY_E_ARGUMENT'],
    [['help', 'encode', 'extra'],                                  2, 'RTTY_E_ARGUMENT'],
    [['encode', '--typo'],                                         2, 'RTTY_E_ARGUMENT'],
    [['encode', '--unk', 'skip'],                                  2, 'RTTY_E_ARGUMENT'],
    [['encode', '--UNKNOWN', 'skip'],                              2, 'RTTY_E_ARGUMENT'],
    [['encode', '--input'],                                        2, 'RTTY_E_ARGUMENT'],
    [['encode', '--unknown', 'error', '--unknown', 'skip', 'SOS'], 2, 'RTTY_E_ARGUMENT'],
    [['encode', '-i', '-', '--input', '-'],                        2, 'RTTY_E_ARGUMENT'],
    [['encode', '-i', '-', 'SOS'],                                 2, 'RTTY_E_ARGUMENT'],
    [['encode', '--overwrite', 'SOS'],                             2, 'RTTY_E_ARGUMENT'],
    [['wav', 'SOS'],                                               2, 'RTTY_E_ARGUMENT'],
    [['midi', 'SOS'],                                              2, 'RTTY_E_ARGUMENT'],
    [['encode', '--max-input-bytes', '0', 'SOS'],                  2, 'RTTY_E_ARGUMENT'],
    [['encode', '--max-input-bytes', '2', 'SOS'],                  3, 'RTTY_E_RESOURCE'],
    [['encode', 'A' x 8193],                                       3, 'RTTY_E_RESOURCE'],
    [['encode', '!'],                                              3, 'RTTY_E_SYMBOL'],
    [['decode', '.........'],                                      3, 'RTTY_E_SYMBOL'],
    [['encode', "\xff"],                                           3, 'RTTY_E_SYMBOL'],
    [['receive', 'a.wav', 'b.wav'],                                2, 'RTTY_E_ARGUMENT'],
    [['receive', '--input', 'a.wav', 'b.wav'],                     2, 'RTTY_E_ARGUMENT'],
    [['receive', '--max-bytes', '1'],                              2, 'RTTY_E_ARGUMENT'],
    [['wav', '-o', '-', '--wpm', '0', 'SOS'],                      2, 'RTTY_E_ARGUMENT'],
    [['wav', '-o', '-', '--bits', '12', 'SOS'],                    2, 'RTTY_E_ARGUMENT'],
    [['midi', '-o', '-', '--note', '128', 'SOS'],                  2, 'RTTY_E_ARGUMENT']
    )
{
    ($status, $out, $err) = cli($case->[0]);
    is($status, $case->[1], 'invalid command/input has documented exit status');
    is($out,    '',         'failure leaves stdout empty');
    like($err, qr/\Aham-rtty: $case->[2]: /, 'failure carries stable error code');
    unlike($err, qr/ at .* line \d/, 'failure hides Perl traceback');
}
for my $input ("\xff", "\xed\xa0\x80", "\xf0\x80\x80\x80", "\xc3") {
    ($status, $out, $err) = cli(['encode'], $input);
    is($status, 3, 'malformed UTF-8 is rejected');
    like($err, qr/RTTY_E_SYMBOL/, 'encoding failure is structured');
}
($status, $out, $err) = cli(['encode', '--max-input-bytes', '2'], 'SOS');
is($status, 3, 'stdin byte limit is enforced');
my $root  = tempdir(CLEANUP => 1);
my $input = File::Spec->catfile($root, 'UTF-8 input.txt');
open my $file, '>:raw', $input or die $!;
print {$file} "\xef\xbb\xbf\xc3\x89\r\n" or die $!;
close $file                              or die $!;
($status, $out) = cli(['encode', '--input', $input]);
is($status, 0,         'UTF-8 file path with spaces succeeds');
is($out,    "..-..\n", 'UTF-8 file is decoded independently of shell encoding');
my $output = File::Spec->catfile($root, 'output text.txt');
($status, $out, $err) = cli(['encode', '--output', $output, 'SOS']);
is($status,             0,               'named text output succeeds');
is($out,                '',              'named output does not duplicate stdout');
is(file_bytes($output), "... --- ...\n", 'named output contains conversion');
($status, $out, $err) = cli(['encode', '--output', $output, 'CQ']);
is($status,             3,               'existing output is protected');
is(file_bytes($output), "... --- ...\n", 'protected contents are unchanged');
($status) = cli(['encode', '--output', $output, '--overwrite', 'CQ']);
is($status,             0,             'explicit overwrite succeeds');
is(file_bytes($output), "-.-. --.-\n", 'replacement contains new conversion');
($status) = cli(['encode', '--output', $output, '--overwrite', '!']);
is($status,             3,             'failed replacement reports invalid data');
is(file_bytes($output), "-.-. --.-\n", 'failed replacement preserves destination');
($status, $out, $err) = cli(['encode', '--input', File::Spec->catfile($root, 'absent')]);
is($status, 3, 'missing input file is an I/O failure');
my $events;
($status, $out) = cli(['events', '--wpm', '20', 'E']);
$events = decode_json($out);
is_deeply(
    $events,
    {unit => 'us', segments => [{state => 'on', duration => 60000}]},
    'timed event JSON matches independent vector'
);
($status, $out) = cli(['events', '--sample-rate', '8000', 'E']);
$events = decode_json($out);
is_deeply(
    $events,
    {sample_rate => 8000, segments => [{state => 'on', samples => 480}]},
    'sampled event JSON matches independent vector'
);
($status, $out) = cli(['events', '--wpm', '20', '--effective-wpm', '10', 'EE']);
$events = decode_json($out);
cmp_ok($events->{segments}[1]{duration}, '>', 180000, 'Farnsworth option extends letter gaps');
my $wav;
($status, $wav, $err) =
    cli(['wav', '-o', '-', '--sample-rate', '8000', '--frequency', '650', 'SOS']);
is($status,                          0,      'binary WAV stdout succeeds');
is(substr($wav, 0, 4),               'RIFF', 'WAV stdout starts with a binary RIFF header');
is($err,                             '',     'WAV stdout has no mixed diagnostics');
is(unpack('V', substr($wav, 24, 4)), 8000,   'requested sample rate reaches WAV header');

for my $arguments (
    ['receive', '--frequency', '650', '--wpm', '20'],
    ['receive', '-',       '--frequency', '650',         '--wpm', '20'],
    ['receive', '--input', '-',           '--frequency', '650',   '--wpm', '20']
    )
{
    ($status, $out, $err) = cli($arguments, $wav);
    is($status, 0,       'WAV stdin reception succeeds');
    is($out,    "SOS\n", 'WAV stdin yields expected text');
    is($err,    '',      'clean reception has no warning');
}
($status, $out, $err) = cli(['receive', '--json', '--frequency', '650', '--wpm', '20'], $wav);
is(decode_json($out)->{text}, 'SOS', 'receive JSON is valid and includes decoded text');
is($err,                      '',    'JSON diagnostics remain in the result object');
($status, $out, $err) = cli(['receive', '--max-bytes', '44'], $wav);
is($status, 3, 'WAV stdin spooling enforces byte limit');
like($err, qr/RTTY_E_RESOURCE/, 'WAV stdin limit reports resource error');
($status, $out, $err) = cli(['receive'], 'not a WAV file');
is($status, 3, 'malformed WAV is a data error');
($status, $out, $err) = cli(['receive'], Ham::RTTY->new->wav_bytes(''));
is($status, 1, 'empty reception returns status 1');
like($err, qr/RTTY_W_NO_SIGNAL/, 'text mode exposes reception warning');
($status, $out, $err) = cli(['receive', '--json'], Ham::RTTY->new->wav_bytes(''));
is($status, 1, 'empty JSON reception returns status 1');
ok(@{decode_json($out)->{warnings}}, 'JSON exposes rejection warnings');
is($err, '', 'JSON rejection warnings do not contaminate stderr');
my $spaced = Ham::RTTY->new(wpm => 20, effective_wpm => 10, sample_rate => 8000, frequency => 650)
    ->wav_bytes('CQ TEST');
my (undef, $provisional_text) = cli(['receive', '--wpm', '20', '--frequency', '650'], $spaced);
($status, $out, $err) = cli(['receive', '--wpm', '20', '--frequency', '650', '--strict'], $spaced);
is($status, 1,                 'strict reception rejects a warning even with text');
is($out,    $provisional_text, 'strict status preserves recovered text for inspection');
like($err, qr/RTTY_W_SPACING_AMBIGUOUS/, 'missing spacing hint is visible');
($status, $out, $err) =
    cli(['receive', '--wpm', '20', '--effective-wpm', '10', '--frequency', '650', '--strict'],
    $spaced);
is($status, 0,           'strict reception succeeds with usable spacing hints');
is($out,    "CQ TEST\n", 'spacing hint reaches the library decoder');

for my $format (qw(wav midi)) {
    my $path = File::Spec->catfile($root, "generated.$format");
    ($status, $out) = cli([$format, '--output', $path, 'SOS']);
    is($status, 0,  "named $format export succeeds");
    is($out,    '', 'file export leaves stdout empty');
    like(file_bytes($path), $format eq 'wav' ? qr/\ARIFF/ : qr/\AMThd/, 'export has correct magic');
    ($status) = cli([$format, '--output', $path, 'SOS']);
    is($status, 3, 'binary destination is protected');
    my $before = file_bytes($path);
    ($status) = cli([$format, '--output', $path, '--overwrite', '!']);
    is($status,           3,       'failed binary replacement reports data error');
    is(file_bytes($path), $before, 'failed binary replacement preserves bytes');
}
($status, $out) = cli(['receive', File::Spec->catfile($root, 'generated.wav')]);
is($out, "SOS\n", 'receive accepts a positional path');
($status, $out) = cli(['receive', '--input', File::Spec->catfile($root, 'generated.wav')]);
is($out, "SOS\n", 'receive accepts an explicit input path');
($status, $out) = cli(['midi', '--output', '-', '--note', '60', '--channel', '3', 'E']);
is($status,            0,      'binary MIDI stdout succeeds');
is(substr($out, 0, 4), 'MThd', 'MIDI stdout contains raw SMF');
like($out, qr/\x92\x3c\x64/, 'MIDI note/channel options reach note-on event');
{
    no warnings 'redefine';
    local *Ham::RTTY::new = sub { die "private internal failure\n" };
    ($status, $out, $err) = cli(['encode', 'SOS']);
    is($status, 4, 'unexpected exception has its own exit status');
    like($err, qr/RTTY_E_INTERNAL/, 'unexpected exception is identified');
    unlike($err, qr/private internal failure/, 'internal details are not leaked');
}
for my $fault (
    {in  => {binmode => 1}},
    {out => {binmode => 1}},
    {in  => {read    => 1}},
    {out => {print   => 1}}
    )
{
    ($status, $out, $err) = cli(['encode'], 'SOS', $fault);
    is($status, 3, 'standard-stream I/O failure returns status 3');
    like($err, qr/RTTY_E_IO/, 'standard-stream failure has a stable diagnostic');
}
($status) = cli(['unknown'], '', {err => {print => 1}});
is($status, 3, 'failed error reporting remains an I/O failure');
{
    no warnings 'redefine';
    local *Ham::RTTY::_Internal::CLI::tempfile = sub { die "temporary storage unavailable\n" };
    ($status, $out, $err) = cli(['receive'], $wav);
    is($status, 3, 'temporary input creation failure is catchable');
    like($err, qr/RTTY_E_IO/, 'temporary input creation failure is an I/O error');
}
for my $operation ('binmode', 'seek') {
    no warnings 'redefine';
    my $temporary = gensym();
    tie *{$temporary}, 'FaultHandle', fail => {$operation => 1};
    local *Ham::RTTY::_Internal::CLI::tempfile = sub { return $temporary };
    ($status, $out, $err) = cli(['receive'], $wav);
    is($status, 3, "temporary input $operation failure is catchable");
    like($err, qr/RTTY_E_IO/, 'temporary input operation failure is an I/O error');
}
done_testing;
