#!/usr/bin/env perl
use 5.020;
use strict;
use warnings;
use Carp qw(croak);
use CPAN::Audit 20261013.002;
use CPAN::Meta;
use CPAN::Meta::Requirements;
use CPANSA::DB;
use JSON::PP;
use PPI 1.291;

# CPAN::Audit remains responsible for advisory matching. This adapter repairs
# inventory/constraint discovery only; it has no advisory exclusion mechanism.
sub module_name {
    my ($path) = @_;
    open my $input, '<', $path or croak "Cannot inspect module $path: $!";
    my $name = package_from_handle($input, $path);
    close $input or croak "Cannot close module $path: $!";
    return $name;
}

sub package_from_handle {
    my ($input, $path) = @_;
    my $source  = '';
    my $pending = 0;
    while (my $line = <$input>) {
        $source .= $line;
        $pending ||= $line =~ /\bpackage\b/x;
        next unless $pending && $line =~ /[;{]/x;
        my $document = PPI::Document->new(\$source);
        my $package  = $document && $document->find_first('PPI::Statement::Package');
        if ($package) {
            return $package->namespace;
        }
        $pending = 0;
    }
    my $document = PPI::Document->new(\$source);
    croak "Cannot inspect module $path" unless $document;
    my $package = $document->find_first('PPI::Statement::Package');
    return $package ? $package->namespace : undef;
}

sub declared_ranges {
    my ($metadata, $database) = @_;
    my $prereqs = $metadata->prereqs;
    my $minimum = $prereqs->{runtime}{requires}{perl};
    croak 'Missing explicit Perl requirement' unless $minimum;
    my @scopes;
    for my $phase (sort keys %{$prereqs}) {
        for my $relation (sort keys %{$prereqs->{$phase}}) {
            croak "Unsupported prerequisite relation $relation"
                unless $relation eq 'requires' || $relation eq 'recommends';
            my $distributions = CPAN::Meta::Requirements->new;
            $distributions->add_string_requirement('perl', $minimum);
            my @unmapped;
            for my $module (sort keys %{$prereqs->{$phase}{$relation}}) {
                my $range = $prereqs->{$phase}{$relation}{$module};
                my $dist  = $module eq 'perl' ? 'perl' : $database->{module2dist}{$module};
                if (!defined $dist) { push @unmapped, $module; next }
                if ($dist eq 'perl' && $module ne 'perl') {
                    croak
"Cannot map nonzero core-module requirement $module $range to a Perl release"
                        if $range ne '0';
                    next;
                }
                croak "Cannot map module version to distribution version: $module $range ($dist)"
                    if $range ne '0'
                    && $module ne 'perl'
                    && $database->{dists}{$dist}{main_module} ne $module;
                $distributions->add_string_requirement($dist, $range);
            }
            push @scopes,
                {
                phase            => $phase,
                relation         => $relation,
                ranges           => $distributions->as_string_hash,
                unmapped_modules => \@unmapped
                };
        }
    }
    return \@scopes;
}

sub installed_report {
    my ($audit, @directories) = @_;

    # Stock discovery mistakes "package Pod::Man v6.1.1;" for a module named
    # "Pod::Man v6.1.1". Parse source without loading or executing the module.
    local *CPAN::Audit::Installed::module_from_file = \&module_name;
    return $audit->command('installed', @directories);
}

sub declared_report {
    my ($path, $database) = @_;
    my $scopes = declared_ranges(CPAN::Meta->load_file($path), $database);
    my $audit  = CPAN::Audit->new(db => $database, no_corelist => 1, quiet => 1);
    my $report = {
        meta => {
            command          => 'declared',
            args             => [$path],
            cpan_audit       => {version => $CPAN::Audit::VERSION, db => $CPANSA::DB::VERSION},
            total_advisories => 0,
            scopes           => $scopes
        },
        errors => [],
        dists  => {},
    };
    my %seen;
    for my $scope (@{$scopes}) {
        for my $dist (sort keys %{$scope->{ranges}}) {
            my $range  = $scope->{ranges}{$dist};
            my $result = $audit->command('dist', $dist, $range);
            push @{$report->{errors}}, @{$result->{errors}};
            next unless $result->{dists}{$dist};
            my $entry = $report->{dists}{$dist} //= {advisories => [], scopes => []};
            push @{$entry->{scopes}},
                {phase => $scope->{phase}, relation => $scope->{relation}, version => $range};
            for my $advisory (@{$result->{dists}{$dist}{advisories}}) {
                next if $seen{$dist}{$advisory->{id}}++;
                push @{$entry->{advisories}}, $advisory;
                ++$report->{meta}{total_advisories};
            }
        }
    }
    return $report;
}

sub main {
    my ($mode, $path, $raw_directory) = @ARGV;
    croak
'Usage: perl maint/audit-dependencies.pl installed | declared MYMETA.json CPANFILE_DIRECTORY'
        unless defined($mode)
        && (($mode eq 'installed' && @ARGV == 1)
        || ($mode eq 'declared' && @ARGV == 3));
    my $database = CPANSA::DB->db;
    my $audit    = CPAN::Audit->new(db => $database, include_perl => 1, quiet => 1);
    my $raw =
          $mode eq 'installed'
        ? $audit->command('installed')
        : $audit->command('deps', $raw_directory);
    my $report =
        $mode eq 'installed' ? installed_report($audit) : declared_report($path, $database);
    $report->{stock_report} = $raw;
    push @{$report->{errors}}, @{$raw->{errors}};
    print JSON::PP->new->utf8->canonical->pretty->encode($report)
        or croak 'Cannot write audit report';
    return @{$report->{errors}} ? 2 : $report->{meta}{total_advisories} ? 1 : 0;
}

exit main() unless caller;
1;
