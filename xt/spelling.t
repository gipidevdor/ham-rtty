use strict;
use warnings;
use Test::More;
my $available = system('codespell', '--version');
plan skip_all => 'Install codespell for author spelling checks' if $available != 0;
my @files = (
    'README.md', 'CONTRIBUTING.md', 'SECURITY.md', 'Changes', 'lib', 'bin', 'docs', 'examples',
    'corpus/README.md', 'corpus/real/LICENSES.md'
);
is(system('codespell', '--quiet-level', '2', @files), 0, 'documentation spelling');
done_testing;
