#!/usr/bin/env perl
use 5.020;
use strict;
use warnings;
use Archive::Tar 3.10;
use Module::CPANTS::Analyse;
use JSON::PP;
use CPAN::Meta;
use ExtUtils::MakeMaker ();
use File::Spec;

my ($path) = @ARGV;
die "Usage: perl maint/check-dist.pl DISTRIBUTION.tar.gz\n" unless defined($path) && -f $path;
my $analysis  = Module::CPANTS::Analyse->new({dist => $path});
my $result    = $analysis->run;
my $directory = $analysis->distdir;
my $metadata  = CPAN::Meta->load_file(File::Spec->catfile($directory, 'META.json'));
my %release_checks;
for my $file (
    qw(README README.md LICENSE NOTICE SECURITY.md Changes Makefile.PL MANIFEST META.json META.yml bin/ham-rtty)
    )
{
    $release_checks{"contains:$file"} =
        -s File::Spec->catfile($directory, split m{/}x, $file) ? 1 : 0;
}
$release_checks{static_prerequisites} = $metadata->dynamic_config ? 0 : 1;
$release_checks{archive_version_matches_metadata} =
    $result->{version} eq $metadata->version ? 1 : 0;
for my $package (sort keys %{$metadata->provides}) {
    my $provided = $metadata->provides->{$package};
    my $file     = File::Spec->catfile($directory, split m{/}x, $provided->{file});
    $release_checks{"indexed_version:$package"} =
           -f $file
        && MM->parse_version($file) eq $provided->{version}
        && $provided->{version} eq $metadata->version ? 1 : 0;
    $release_checks{"index_allowed:$package"} = $metadata->should_index_file($provided->{file})
        && $metadata->should_index_package($package) ? 1 : 0;
}
my @failed         = sort grep { !$result->{kwalitee}{$_} } keys %{$result->{kwalitee}};
my @release_failed = sort grep { !$release_checks{$_} } keys %release_checks;
my $report         = {
    checks         => $result->{kwalitee},
    release_checks => \%release_checks,
    diagnostics    => $result->{error} // {},
};
print JSON::PP->new->canonical->pretty->encode($report);
die "Failed archive indicators: @failed\n"       if @failed;
die "Failed release contract: @release_failed\n" if @release_failed;
die "Archive diagnostics require review\n"       if keys %{$report->{diagnostics}};
