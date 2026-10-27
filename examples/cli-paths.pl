#!/usr/bin/env perl
use 5.020;
use strict;
use warnings;
use Carp       qw(croak);
use File::Temp qw(tempdir tempfile);
use File::Spec;
use FindBin;
use IPC::Open3 qw(open3);
use JSON::PP;
use Ham::RTTY;

my $backend  = shift @ARGV // 'perl';
my $cw       = Ham::RTTY->new(sample_rate => 8000, frequency => 650, backend => $backend);
my $command  = File::Spec->catfile($FindBin::Bin, '..', 'bin', 'ham-rtty');
my @includes = map { '-I' . $_ } grep { !ref $_ } @INC;

sub command {
    my ($arguments, $input) = @_;
    my ($in)  = tempfile(TMPDIR => 1, UNLINK => 1);
    my ($out) = tempfile(TMPDIR => 1, UNLINK => 1);
    my ($err) = tempfile(TMPDIR => 1, UNLINK => 1);
    binmode $_, ':raw' or croak $! for $in, $out, $err;
    print {$in} $input // '' or croak $!;
    seek $in, 0, 0 or croak $!;

    # File redirections avoid pipe-buffer deadlocks and preserve binary bytes.
    # IPC::Open3 duplicates numeric file descriptors in the child.
    my ($read, $write, $error) = ('<&' . fileno($in), '>&' . fileno($out), '>&' . fileno($err));
    my $pid = open3($read, $write, $error, $^X, @includes, $command, @{$arguments});
    waitpid($pid, 0) == $pid or croak $!;
    my $status = $?;
    seek $_, 0, 0 or croak $! for $out, $err;
    my $stdout = do { local $/ = undef; <$out> };
    my $stderr = do { local $/ = undef; <$err> };
    close $_ or croak $! for $out, $err;
    croak 'Child terminated by signal' if $status & 127;
    return ($status >> 8, $stdout, $stderr);
}

sub text_commands {
    my ($status, $text, $diagnostic) = command(['encode'], "SOS\r\n");
    croak 'CLI stdin failed' unless $status == 0 && $text eq "... --- ...\n";
    ($status, $text) = command(['decode', '--', '-.. .']);
    croak 'Dash-leading decode failed' unless $status == 0 && $text eq "DE\n";
    for my $options ([], ['--sample-rate', '8000']) {
        ($status, $text) = command(['events', @{$options}, 'SOS']);
        croak 'CLI events failed' unless $status == 0 && @{decode_json($text)->{segments}};
    }
    my $directory = tempdir(CLEANUP => 1);
    my $input     = File::Spec->catfile($directory, 'utf8.txt');
    my $output    = File::Spec->catfile($directory, 'morse.txt');
    open my $file, '>:raw', $input or croak $!;
    print {$file} "\xc3\x89\r\n" or croak $!;
    close $file                  or croak $!;
    ($status) = command(['encode', '--input', $input, '--output', $output]);
    croak 'Named UTF-8 input failed' unless $status == 0;
    open my $read, '<:raw', $output or croak $!;
    my $morse = do { local $/ = undef; <$read> };
    close $read or croak $!;
    croak 'UTF-8 file converted incorrectly' unless $morse eq "..-..\n";

    ($status, $text) = command(['encode'], "\xc3\x89\r\n");
    croak 'UTF-8 stdin converted incorrectly' unless $status == 0 && $text eq "..-..\n";
    for my $arguments (['help', 'receive'], ['--version']) {
        ($status, $text) = command($arguments);
        croak 'Help/version failed' unless $status == 0 && length $text;
    }
    return;
}

sub binary_commands {
    my ($status, $text, $diagnostic);
    my $wave;
    ($status, $wave) = command(
        [
            'wav',  '--backend', $backend, '--frequency', '650', '--sample-rate',
            '8000', '--output',  '-',      'SOS'
        ]
    );
    croak 'Binary WAV stdout failed' unless $status == 0 && substr($wave, 0, 4) eq 'RIFF';
    ($status, $text, $diagnostic) =
        command(['receive', '--backend', $backend, '--json', '--frequency', '650', '--wpm', '20'],
        $wave);
    croak 'WAV stdin reception failed'
        unless $status == 0 && decode_json($text)->{text} eq 'SOS' && $diagnostic eq '';
    ($status, $text) = command(
        [
            'receive', '--backend', $backend, '--all-stations', '--json', '--frequency',
            '650',     '--wpm',     '20'
        ],
        $wave
    );
    croak 'Channel JSON failed' unless $status == 0 && ref(decode_json($text)) eq 'ARRAY';
    ($status, $text) = command(['midi', '--output', '-', 'SOS']);
    croak 'Binary MIDI stdout failed' unless $status == 0 && substr($text, 0, 4) eq 'MThd';

    return;
}

sub status_commands {
    my ($status);
    ($status) =
        command(['receive', '--backend', $backend, '--strict', '--json', '--frequency', '650'],
        $cw->wav_bytes(''));
    croak 'Expected reception status 1' unless $status == 1;
    ($status) = command(['encode', '--unknown-option']);
    croak 'Expected usage status 2' unless $status == 2;
    ($status) = command(['encode', '--max-input-bytes', '1', 'SOS']);
    croak 'Expected resource status 3' unless $status == 3;
    return;
}

text_commands();
binary_commands();
status_commands();
print
"CLI text, events, binary stdout, WAV stdin, files, station JSON and exit statuses 0/1/2/3 checked.\n";
print "Example completed: cli-paths\n";
