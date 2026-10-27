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
done_testing;
