use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir tempfile);
use File::Spec;
use Cwd qw(abs_path);
use JSON::PP;
use IPC::Open3 qw(open3);

my $root = abs_path('.');

sub read_text {
    my ($path) = @_;
    open my $input, '<', $path or die $!;
    my $text = do { local $/; <$input> };
    close $input or die $!;
    return $text;
}

sub execute_example {
    my ($name, @arguments) = @_;
    my $temporary = tempdir(CLEANUP => 1);
    my ($in)      = tempfile(TMPDIR => 1, UNLINK => 1);
    my ($out)     = tempfile(TMPDIR => 1, UNLINK => 1);
    my ($err)     = tempfile(TMPDIR => 1, UNLINK => 1);
    binmode $_, ':raw' or die $! for $in, $out, $err;
    no warnings 'once';
    local *EXAMPLE_PROCESS_IN  = $in;
    local *EXAMPLE_PROCESS_OUT = $out;
    local *EXAMPLE_PROCESS_ERR = $err;
    my ($read, $write, $error) = (
        '<&main::EXAMPLE_PROCESS_IN', '>&main::EXAMPLE_PROCESS_OUT', '>&main::EXAMPLE_PROCESS_ERR'
    );
    chdir $temporary or die $!;

    # Wait for the directly spawned process before reading or removing its
    # output files; an extra exec wrapper races handle cleanup on Windows.
    my $pid = open3(
        $read, $write, $error, $^X, '-Mwarnings=FATAL,all',
        '-I' . File::Spec->catdir($root, 'lib'),
        File::Spec->catfile($root, 'examples', $name), @arguments
    );
    waitpid($pid, 0) == $pid or die $!;
    my $status = $?;
    chdir $root or die $!;
    seek $_, 0, 0 or die $! for $out, $err;
    my $output     = do { local $/; <$out> };
    my $diagnostic = do { local $/; <$err> };
    close $_ or die $! for $out, $err;
    return ($status, ($output // '') . ($diagnostic // ''));
}

my $routes   = decode_json(read_text('examples/routes.json'));
my @backends = ('perl');
push @backends, 'pdl', 'auto' if eval { require PDL; PDL->VERSION('2.081'); 1 };
my (%covered, %files, %commands);
for my $route (@{$routes}) {
    ok(!$files{$route->{file}}++, "$route->{file} is listed once");
    for my $module (keys %{$route->{methods}}) {
        $covered{"$module.$_"} = 1 for @{$route->{methods}{$module}};
    }
    $commands{$_} = 1 for @{$route->{commands} // []};
    for my $backend ($route->{backend} ? @backends : ('perl')) {
        my @arguments = $route->{backend} ? ($backend) : ();
        my ($status, $output) = execute_example($route->{file}, @arguments);
        is($status, 0, "$route->{file} / $backend executes independently") or diag($output);
        (my $name = $route->{file}) =~ s/\.pl\z//x;
        my $completion =
            $name eq 'workflows'
            ? qr/All[ ]workflows[ ]completed/x
            : qr/Example[ ]completed:[ ]\Q$name\E/x;
        like($output, $completion, "$route->{file} / $backend actually completes");
    }
}
my %manual  = map { $_ => 1 } qw(send.pl receive.pl midi.pl run-all.pl);
my @scripts = map { s{\Aexamples/}{}r } sort glob 'examples/*.pl';
is_deeply(
    [sort keys %files],
    [grep { !$manual{$_} } @scripts],
    'every self-contained example is catalogued'
);
for my $path ('lib/Ham/RTTY.pm', sort glob 'lib/Ham/RTTY/*.pm') {
    my $text   = read_text($path);
    my ($code) = split /^=encoding UTF-8\s*$/m, $text, 2;
    (my $module = $path) =~ s{\Alib/|\.pm\z}{}gx;
    $module =~ s{/}{::}gx;
    for my $method ($code =~ /^sub ([a-z][A-Za-z0-9_]*)\b/mg) {
        ok(delete $covered{"$module.$method"}, "$module.$method has an executable example");
    }
    if ($module eq 'Ham::RTTY::Audio') {
        my ($writer) = $text =~ /^=head1 WRITER OPERATIONS\s*\n(.*?)(?=^=head1|\z)/ms;
        ok(defined $writer, 'returned WAV writer operations are documented');
        for my $method (($writer // '') =~ /^=head2 ([a-z][A-Za-z0-9_]*)\s*$/mg) {
            ok(delete $covered{"WAV writer.$method"}, "returned WAV writer.$method has an example");
        }
    }
}
is_deeply([sort keys %covered], [], 'catalog contains no unknown public methods');
my ($command_section) = read_text('bin/ham-rtty') =~ /^=head1 COMMANDS\s*\n(.*?)(?=^=head1|\z)/ms;
my @commands = $command_section =~ /^=head2 ([a-z]+)\s*$/mg;
is_deeply(
    [sort keys %commands],
    [sort @commands, 'help', 'version'],
    'all CLI commands are catalogued'
);
my ($status, $output) = execute_example('run-all.pl', '--list');
is($status, 0, 'runner lists examples') or diag($output);
like($output, qr/reception-samples/, 'runner list includes the reception path');
($status, $output) = execute_example('run-all.pl', '--only', 'text-events');
is($status, 0, 'runner executes a selected example from an empty directory') or diag($output);
($status, $output) = execute_example('run-all.pl', '--only', 'unknown');
isnt($status, 0, 'runner rejects a misspelled scenario');
like($output, qr/No matching example/, 'runner rejection is the expected scenario error');
done_testing;
