use strict;
use warnings;
use Test::More;
use File::Temp qw(tempfile);
use IPC::Open3 qw(open3);
use JSON::PP;
use Config;
use Ham::RTTY;

sub child {
    my ($arguments, $input, $broken) = @_;
    my ($in)  = tempfile('ham-rtty-cli-in-XXXXXX',  TMPDIR => 1, UNLINK => 1);
    my ($out) = tempfile('ham-rtty-cli-out-XXXXXX', TMPDIR => 1, UNLINK => 1);
    my ($err) = tempfile('ham-rtty-cli-err-XXXXXX', TMPDIR => 1, UNLINK => 1);
    binmode $_, ':raw' or die $! for $in, $out, $err;
    print {$in} $input // '' or die $!;
    seek $in, 0, 0 or die $!;

    # Named redirections are supported by IPC::Open3 on Perl 5.20 too.
    # Files prevent either output channel from filling a pipe and deadlocking.
    no warnings 'once';
    local *CLI_PROCESS_IN  = $in;
    local *CLI_PROCESS_OUT = $broken // $out;
    local *CLI_PROCESS_ERR = $err;
    my ($read, $write, $error) =
        ('<&main::CLI_PROCESS_IN', '>&main::CLI_PROCESS_OUT', '>&main::CLI_PROCESS_ERR');
    my $pid = open3($read, $write, $error, $^X, '-Ilib', 'bin/ham-rtty', @{$arguments});
    waitpid($pid, 0) == $pid or die $!;
    my $status = $?;
    seek $_, 0, 0 or die $! for $out, $err;
    my $stdout = do { local $/; <$out> };
    my $stderr = do { local $/; <$err> };
    close $_ or die $! for $out, $err;
    return ($status, $stdout, $stderr);
}
my ($status, $out, $err) = child(['encode', 'CQ TEST']);
is($status, 0,                         'executable exits successfully');
is($out,    "-.-. --.- / - . ... -\n", 'quoted argument crosses process boundary intact');
is($err,    '',                        'successful executable has no diagnostic');
($status, $out, $err) = child(['encode'], "SOS\r\n");
is($status, 0,               'executable accepts stdin');
is($out,    "... --- ...\n", 'stdin receives the same conversion');
($status, $out, $err) = child(['encode'], "\xc3\x89\r\n");
is($out, "..-..\n", 'UTF-8 stdin survives the process boundary');
($status, $out, $err) = child(['decode', '--', '-.. .']);
is($out, "DE\n", 'dash-leading argument survives process boundary');
($status, $out, $err) = child(['encode', '<AR>']);
is($out, ".-.-.\n", 'prosign shell metacharacters are literal arguments');
($status, $out, $err) = child(['--version']);
is($out, "ham-rtty $Ham::RTTY::VERSION\n", 'executable version matches distribution');
($status, $out, $err) = child(['encode', '--unknown-option']);
is($status >> 8,  2,  'usage error reaches process exit status');
is($status & 127, 0,  'usage error does not signal');
is($out,          '', 'usage error does not write stdout');
like($err, qr/RTTY_E_ARGUMENT/, 'usage error is reported on stderr');
my $wave;
($status, $wave, $err) =
    child(['wav', '--output', '-', '--frequency', '650', '--sample-rate', '8000', 'SOS']);
is($status,                              0,             'executable emits binary WAV');
is(unpack('V', substr($wave, 4, 4)) + 8, length($wave), 'WAV byte count survives stdio');
($status, $out, $err) = child(['receive', '--json', '--frequency', '650', '--wpm', '20'], $wave);
is($status,                   0,     'executable receives WAV from redirected stdin');
is(decode_json($out)->{text}, 'SOS', 'executable JSON is uncontaminated and correct');
is($err,                      '',    'clean receive JSON has no diagnostic output');
($status, $out, $err) = child(['midi', '--output', '-', 'SOS']);
is($status,                               0,            'executable emits binary MIDI');
is(unpack('N', substr($out, 18, 4)) + 22, length($out), 'MIDI byte count survives stdio');
SKIP: {
    skip 'SIGPIPE is not available', 6 unless $Config{sig_name} =~ /\bPIPE\b/x;
    pipe(my $reader, my $writer) or die $!;
    close $reader                or die $!;
    for my $arguments (['--help'], ['wav', '--output', '-', 'SOS']) {
        ($status, $out, $err) = child($arguments, '', $writer);
        is($status & 127, 0, 'broken output pipe does not terminate by signal');
        is($status >> 8,  3, 'broken output pipe has documented exit status');
        like($err, qr/RTTY_E_IO/, 'broken output pipe has an I/O diagnostic');
    }
    close $writer;
}
done_testing;
