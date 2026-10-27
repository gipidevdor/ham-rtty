#!/usr/bin/env perl
use 5.020;
use strict;
use warnings;
use Devel::Cover::DB;
use JSON::PP;
use File::Find qw(find);
use File::Spec;
use FindBin;

my ($path) = @ARGV;
die "Usage: perl maint/coverage.pl COVER_DB\n" unless defined $path;
my $db = Devel::Cover::DB->new(db => $path);
$db = $db->merge_runs;
my $root = File::Spec->rel2abs("$FindBin::Bin/..");
my %expected;
find(
    {
        no_chdir => 1,
        wanted   => sub {
            return unless /\.pm\z/x && -f $_;
            my $relative = File::Spec->abs2rel($File::Find::name, $root);
            $relative =~ tr{\\}{/};
            $expected{$relative} = 1;
        }
    },
    "$root/lib"
);
die "No production source modules found\n" unless keys %expected;
my %observed;
for my $path ($db->cover->items) {
    next unless $path =~ m{(?:\A|[\\/])(lib[\\/]Ham[\\/]RTTY(?:\.pm|[\\/].*\.pm))\z}x;
    my $relative = $1;
    $relative =~ tr{\\}{/};
    die "Unexpected production coverage: $path\n" unless $expected{$relative};
    die "Duplicate production coverage for $relative; collect one source tree\n"
        if exists $observed{$relative};
    $observed{$relative} = $path;
}
my @missing = sort grep { !exists $observed{$_} } keys %expected;
die "Missing production module coverage: @missing\n" if @missing;
my @files = map { $observed{$_} } sort keys %expected;
my (%modules, @failures);
for my $relative (sort keys %observed) {
    $db->calculate_summary(
        files     => [$observed{$relative}],
        statement => 1,
        branch    => 1,
        force     => 1
    );
    my $summary = $db->summary('Total');
    $modules{$relative} = $summary;
    for my $gate ([statement => 95], [branch => 90]) {
        my ($criterion, $minimum) = @{$gate};
        my $actual = $summary->{$criterion}{percentage};

        # Modules containing no branch points have no branch percentage.
        next if $criterion eq 'branch' && !defined($actual) && !$summary->{$criterion}{total};
        push @failures, "$relative: missing $criterion coverage" unless defined $actual;
        push @failures, "$relative: $criterion coverage $actual is below $minimum"
            if defined($actual) && $actual < $minimum;
    }
}
$db->calculate_summary(files => \@files, statement => 1, branch => 1, force => 1);
print JSON::PP->new->canonical->pretty->encode(
    {modules => \%modules, total => $db->summary('Total')});
die join("\n", @failures) . "\n" if @failures;
