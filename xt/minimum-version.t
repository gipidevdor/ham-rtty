use strict;
use warnings;
use Test::More;
use File::Find qw(find);
use Perl::MinimumVersion;
use version;
my @files = ('bin/ham-rtty');
find(sub { push @files, $File::Find::name if /\.pm\z/x }, 'lib');

for my $file (sort @files) {
    my $analysis = Perl::MinimumVersion->new($file);
    ok($analysis, "parse $file");
    my $minimum = $analysis->minimum_version;
    cmp_ok(
        version->parse($minimum // '5.000'), '<=',
        version->parse('5.020'),             "$file supports Perl 5.20"
    );
}
done_testing;
