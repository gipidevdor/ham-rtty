use strict;
use warnings;
use Test::More;
use File::Find qw(find);
use Perl::Critic;
my @files;
find(sub { push @files, $File::Find::name if /\.(?:pm|pl)\z/x }, qw(lib maint examples));
my $critic = Perl::Critic->new(-profile => '.perlcriticrc');

for my $file (sort @files, 'Makefile.PL', 'bin/ham-rtty') {
    my @violations = $critic->critique($file);
    is(scalar @violations, 0, $file) or diag(join '', @violations);
}
done_testing;
