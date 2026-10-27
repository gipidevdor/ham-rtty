use 5.020;
use strict;
use warnings FATAL => 'all';
use Test::More;
use File::Temp qw(tempdir);
use Ham::RTTY::_Internal::CLI;

sub run_cli {
    my ($input,  @args)   = @_;
    my ($stdout, $stderr) = ('', '');
    open my $in,  '<', \$input  or die $!;
    open my $out, '>', \$stdout or die $!;
    open my $err, '>', \$stderr or die $!;
    my $status = Ham::RTTY::_Internal::CLI::run(\@args, $in, $out, $err);
    close $_ or die $! for $in, $out, $err;
    return ($status, $stdout, $stderr);
}
my ($status, $out, $err) = run_cli('', 'encode', 'A');
is($status, 0,                'encode status');
is($out,    "[LTRS] 00011\n", 'encode output');
is($err,    '',               'clean stderr');
($status, $out) = run_cli('[LTRS] 00011', 'decode');
is($out, "A\n", 'decode stdin');
($status, $out) = run_cli('', 'bits', 'A');
like($out, qr/\A[01]+\n\z/, 'bits');

for my $verb (qw(encode decode bits events wav midi receive)) {
    ($status, $out) = run_cli('', 'help', $verb);
    is($status, 0, "help $verb");
    like($out, qr/Usage:/, 'help usage');
}
for my $args (
    [], ['wrong'],
    ['encode', '--baud', 19, 'A'],
    ['wav',    'A'],
    ['encode', '--overwrite', 'A'],
    ['encode', '--baud', 50, '--baud', 75, 'A'],
    ['encode', '--missing'],
    ['help',   'wrong']
    )
{
    ($status, $out, $err) = run_cli('', @{$args});
    is($status, 2, 'usage error');
    like($err, qr/RTTY_E_ARGUMENT/, 'stable error code');
}
($status, $out, $err) = run_cli('', 'encode', '@');
is($status, 3, 'unsupported data status');
($status, $out, $err) = run_cli('', 'encode', '--lenient', '@');
is($status, 0, 'lenient status');
like($err, qr/RTTY_W_SYMBOL/, 'lenient warning');
my $dir = tempdir(CLEANUP => 1);
my $wav = "$dir/message.wav";
($status) = run_cli('', 'wav', '--output', $wav, 'CQ 73');
is($status, 0, 'WAV command');
($status, $out) = run_cli('', 'receive', '--json', $wav);
is($status, 0, 'receive command');
like($out, qr/"text"\s*:\s*"CQ 73"/, 'JSON text');
($status) = run_cli('', 'midi', '--output', "$dir/test.mid", 'CQ');
is($status, 0, 'MIDI command');
($status) = run_cli('', 'events', '--sample-rate', 8000, 'A');
is($status, 0, 'sampled events');
($status) = run_cli('', '--version');
is($status, 0, 'version');

for my $args (['--help'], ['-h'], ['encode', '--help'], ['encode', '--version'], ['events', 'A']) {
    ($status, $out) = run_cli('', @{$args});
    is($status, 0, 'global and per-command help/version');
}
($status) = run_cli("\xff", 'encode');
is($status, 3, 'invalid UTF-8 rejected');
($status) = run_cli('AAAA', 'encode', '--max-input-bytes', 1);
is($status, 3, 'stdin byte limit');
($status) = run_cli('', 'encode', '--max-input-bytes', 1, 'AAAA');
is($status, 3, 'positional byte limit');
($status) = run_cli('A' x 70000, 'encode', '--max-input-bytes', 100000);
is($status, 0, 'large input read in bounded blocks');
my $text_path = "$dir/text.txt";
open my $text_out, '>:raw', $text_path or die $!;
print {$text_out} "\xef\xbb\xbfA" or die $!;
close $text_out                   or die $!;
($status, $out) = run_cli('', 'encode', '--input', $text_path);
is($out, "[LTRS] 00011\n", 'UTF-8 file and BOM');
($status) = run_cli('', 'encode', '--input', $text_path, 'A');
is($status, 2, 'mutually exclusive text input');
($status) = run_cli('', 'receive', '--input', $wav, $wav);
is($status, 2, 'mutually exclusive WAV input');
($status) = run_cli('', 'receive', $wav, $wav);
is($status, 2, 'one WAV input only');
my $bytes = Ham::RTTY->new->wav_bytes('CQ');
($status, $out) = run_cli($bytes, 'receive', '--max-bytes', 64000000);
is($status, 0,      'WAV stdin via temporary file');
is($out,    "CQ\n", 'WAV stdin text');
($status) = run_cli($bytes, 'receive', '-');
is($status, 0, 'explicit stdin');
($status) = run_cli($bytes, 'receive', '--max-bytes', 44);
is($status, 3, 'WAV stdin byte ceiling');
my $silence = Ham::RTTY->new(amplitude => 0)->wav_bytes('CQ');
($status, $out, $err) = run_cli($silence, 'receive', '--strict');
is($status, 1, 'strict no-signal status');
like($err, qr/RTTY_W_NO_SIGNAL/, 'receive warnings on stderr');
($status) = run_cli($bytes . 'tail', 'receive', '--strict');
is($status, 1, 'strict warning despite received text');
($status) = run_cli('', 'encode', '--output', "$dir/notation.txt", 'A');
is($status, 0, 'text output path');
($status) = run_cli('', 'encode', '--output', "$dir/notation.txt", '--overwrite', 'B');
is($status, 0, 'text replacement');
my $unicode = 'A';
utf8::upgrade($unicode);
($status) = run_cli('', 'encode', $unicode);
is($status, 0, 'decoded Unicode positional string');
{
    no warnings 'redefine';
    local *Ham::RTTY::encode = sub { die 'injected unexpected error' };
    ($status) = run_cli('', 'decode', '[LTRS] 00011');

    # decode uses its own path; inject that path to verify internal failure handling.
    local *Ham::RTTY::decode = sub { die 'injected unexpected error' };
    ($status) = run_cli('', 'decode', '[LTRS] 00011');
    is($status, 4, 'unexpected internal failure');
}
done_testing;
