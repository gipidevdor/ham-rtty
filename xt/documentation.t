use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use File::Spec;
use Cwd qw(abs_path getcwd);

my $library  = abs_path('lib');
my $original = getcwd();
my @modules  = ('lib/Ham/RTTY.pm', sort glob 'lib/Ham/RTTY/*.pm');

sub read_text {
    my ($path) = @_;
    open my $input, '<:encoding(UTF-8)', $path or die $!;
    local $/;
    my $text = <$input>;
    close $input or die $!;
    return $text;
}

sub run_example {
    my ($source, $label) = @_;
    my $directory = tempdir(CLEANUP => 1);
    my $script    = File::Spec->catfile($directory, 'example.pl');
    my $log       = File::Spec->catfile($directory, 'output.log');
    open my $out, '>:encoding(UTF-8)', $script or die $!;
    print {$out} q{BEGIN {
        open STDOUT, '>', $ENV{HAM_RTTY_DOC_LOG} or die $!;
        open STDERR, '>&', \*STDOUT or die $!;
    }} . "\n" . $source or die $!;
    close $out       or die $!;
    chdir $directory or die $!;
    local $ENV{HAM_RTTY_DOC_LOG} = $log;
    my $status = system $^X, '-Mwarnings=FATAL,all', '-I' . $library, $script;
    chdir $original or die $!;
    is($status, 0, $label) or diag(read_text($log));
    is(read_text($log), "SOS\nSOS\n", 'streamed and collected guide recipes recover the message')
        if $source =~ /my \$collected = \$rtty->decode_samples/;
}
for my $file (@modules) {
    my $source = read_text($file);
    my ($code, $pod) = split /^=encoding UTF-8\s*$/m, $source, 2;
    ok(defined($pod), "$file contains POD");
    like(
        $pod,
        qr/Copyright \(c\) 2026 Giacomo Picchiarelli\./,
        "$file identifies the project copyright holder"
    );
    my %methods = map { $_ => 1 } $code =~ /^sub ([a-z][a-z_]+)\s*\{/mg;
    for my $method (sort keys %methods) {
        like($pod, qr/^=head2 \Q$method\E\s*$/m, "$file documents $method separately");
    }
    my ($synopsis) = $pod =~ /^=head1 SYNOPSIS\s*\n(.*?)(?=^=head1|\z)/ms;
    ok(defined($synopsis), "$file has a standalone synopsis");
    next unless defined $synopsis;
    my $example = join "\n", map { s/^    //r } grep { /^    / } split /\n/, $synopsis;
    run_example($example, "$file synopsis executes");
}
for my $file ('README.md', 'docs/usage.md') {
    my $text     = read_text($file);
    my @examples = $text =~ /^```perl\s*\n(.*?)^```\s*$/msg;
    ok(@examples, "$file contains Perl recipes");
    for my $i (0 .. $#examples) {
        run_example($examples[$i], "$file recipe " . ($i + 1) . ' executes independently');
    }
}
done_testing;
