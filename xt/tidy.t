use strict;
use warnings;
use Test::More;
use File::Find qw(find);
use Perl::Tidy;
my @files = ('Makefile.PL', 'bin/ham-rtty');
find(sub { push @files, $File::Find::name if /\.(?:pm|pl|t)\z/ }, qw(lib t xt examples maint));
for my $file (sort @files) {
    open my $input, '<', $file or die $!;
    my $source = do { local $/; <$input> };
    close $input or die $!;
    my ($destination, $errors);
    my $status = Perl::Tidy::perltidy(
        source      => \$source,
        destination => \$destination,
        stderr      => \$errors,
        perltidyrc  => '.perltidyrc'
    );
    is($status, 0, "tidy parses $file") or diag($errors);
    ok($source eq $destination, "tidy format $file")
        or diag("Run perltidy -b $file using .perltidyrc");
}
done_testing;
