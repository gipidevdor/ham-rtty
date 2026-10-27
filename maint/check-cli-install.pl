#!/usr/bin/env perl
use 5.020;
use strict;
use warnings;
use Config;
use File::Spec;
use File::Temp qw(tempdir);
use Carp       qw(croak);

sub run_command {
    my (@command) = @_;
    system @command;
    croak "Command failed: @command" if $?;
    return;
}

my ($prefix, $build) = @ARGV;
croak "Usage: perl maint/check-cli-install.pl PREFIX [--build]\n"
    if !defined($prefix) || @ARGV > 2 || (defined($build) && $build ne '--build');
$prefix = File::Spec->rel2abs($prefix);
if ($build) {
    run_command($^X, 'Makefile.PL', "INSTALL_BASE=$prefix");
    my $make = $Config{make} || 'make';
    run_command($make);
    run_command($make, 'install');
}
local $ENV{PERL5LIB} = File::Spec->catdir($prefix, 'lib', 'perl5');
my $cli = File::Spec->catfile($prefix, 'bin', $^O eq 'MSWin32' ? 'ham-rtty.bat' : 'ham-rtty');
croak "Installed command is missing: $cli" unless -f $cli;
run_command($cli, '--version');
run_command($cli, 'encode', 'CQ DE TESTCALL');
run_command($cli, 'decode', '--', '[LTRS] 00011');
run_command($cli, 'events', '--sample-rate', '8000', 'E');
my $temporary = tempdir('ham-rtty-installed-cli-XXXXXX', TMPDIR => 1, CLEANUP => 1);
my $wave      = File::Spec->catfile($temporary, 'test message.wav');
my $midi      = File::Spec->catfile($temporary, 'test message.mid');
run_command($cli, 'wav',     '--output', $wave, 'SOS');
run_command($cli, 'receive', '--json',   $wave);
run_command($cli, 'midi',    '--output', $midi, 'SOS');

for my $case ([$wave, 'RIFF'], [$midi, 'MThd']) {
    open my $in, '<:raw', $case->[0] or croak $!;
    my $count = read($in, my $magic, 4);
    croak 'Short or unreadable CLI output' unless defined($count) && $count == 4;
    close $in or croak $!;
    croak 'Invalid CLI output header' unless $magic eq $case->[1];
}
print "Installed command and launcher PASS\n";
