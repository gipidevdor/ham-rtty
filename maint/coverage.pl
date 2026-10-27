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
    next unless $path =~ m{(?:\A|[\\/])(lib[\\/]Ham[\\/]CW(?:\.pm|[\\/].*\.pm))\z}x;
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
$db->calculate_summary(files => \@files, statement => 1, branch => 1, force => 1);
my $summary = $db->summary('Total');
print JSON::PP->new->canonical->pretty->encode($summary);

for my $gate ([statement => 95], [branch => 90]) {
    my ($criterion, $minimum) = @{$gate};
    my $actual = $summary->{$criterion}{percentage};
    die "Missing $criterion coverage\n" unless defined $actual;
    die "$criterion coverage $actual is below $minimum\n" if $actual < $minimum;
}
