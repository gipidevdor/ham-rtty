use strict;
use warnings;
use Test::More;
use Test::CPAN::Meta;
use Test::CPAN::Changes;
use Ham::RTTY ();
use CPAN::Meta;
use CPAN::Meta::Validator;
use CPAN::Meta::Requirements;
use Parse::CPAN::Meta;
use ExtUtils::MakeMaker ();
use ExtUtils::Manifest  qw(maniread);
use File::Spec;
my $meta = -f 'META.yml' ? 'META.yml' : "Ham-RTTY-$Ham::RTTY::VERSION/META.yml";
meta_spec_ok($meta, undef);
changes_file_ok('Changes', {version => $Ham::RTTY::VERSION});

my $directory    = -f 'META.json' ? '.' : "Ham-RTTY-$Ham::RTTY::VERSION";
my @public_files = ('lib/Ham/RTTY.pm', sort glob 'lib/Ham/RTTY/*.pm');
my %expected;
for my $file (@public_files) {
    (my $package = $file) =~ s{\Alib/|\.pm\z}{}gx;
    $package =~ s{/}{::}gx;
    $expected{$package} = {file => $file, version => MM->parse_version($file)};
    is($expected{$package}{version}, $Ham::RTTY::VERSION, "$package shares the release version");
}
my @metas;
for my $format (qw(json yml)) {
    my $path      = File::Spec->catfile($directory, "META.$format");
    my $raw       = Parse::CPAN::Meta->load_file($path);
    my $validator = CPAN::Meta::Validator->new($raw);
    ok($validator->is_valid, "$path conforms to its declared metadata specification")
        or diag(join "\n", $validator->errors);
    my $metadata = CPAN::Meta->new($raw);
    push @metas, $metadata;
    is($metadata->name,    'Ham-RTTY',          "$path names the distribution");
    is($metadata->version, $Ham::RTTY::VERSION, "$path matches the release version");
    ok(!$metadata->dynamic_config, "$path declares static prerequisites");
    is_deeply([$metadata->licenses], ['artistic_2'], "$path declares the project license");
    is_deeply($metadata->provides, \%expected, "$path indexes every public module and no helpers");

    for my $package (sort keys %expected) {
        ok($metadata->should_index_package($package), "$path permits indexing $package");
        ok($metadata->should_index_file($expected{$package}{file}),
            "$path permits its source file");
    }
    for my $file (sort glob 'lib/Ham/RTTY/_Internal/*.pm') {
        (my $package = $file) =~ s{\Alib/|\.pm\z}{}gx;
        $package =~ s{/}{::}gx;
        ok(!$metadata->should_index_package($package), "$path excludes helper namespace $package");
        ok(!$metadata->should_index_file($file),       "$path excludes helper source $file");
    }
    my $prereqs = $metadata->prereqs;
    ok(!exists($prereqs->{runtime}{requires}{PDL}), "$path does not require the native backend");
    is($prereqs->{runtime}{recommends}{PDL}, '2.081', "$path retains optional PDL minimum");
    is($prereqs->{runtime}{requires}{perl},  '5.020', "$path declares minimum Perl");
    is(
        $metadata->resources->{repository}{url},
        'https://github.com/gipidevdor/ham-rtty.git',
        "$path identifies the public repository"
    );
}

sub consumer_requirements {
    my ($metadata) = @_;
    my $requirements = CPAN::Meta::Requirements->new;
    for my $phase (qw(configure build runtime test)) {
        my $phase_requirements = $metadata->prereqs->{$phase}{requires} // {};
        $requirements->add_string_requirement($_, $phase_requirements->{$_})
            for keys %{$phase_requirements};
    }
    return $requirements->as_string_hash;
}
is_deeply(
    consumer_requirements($metas[0]),
    consumer_requirements($metas[1]),
    'JSON and legacy YAML preserve consumer constraints despite merged build/test phases'
);
for my $metadata (@metas) {
    my $requirements = CPAN::Meta::Requirements->new;
    my $combined     = consumer_requirements($metadata);
    $requirements->add_string_requirement($_, $combined->{$_}) for keys %{$combined};
    for my $case (['Encode', '3.11', '3.12'], ['Storable', '3.40', '3.41'], ['Cwd', '3.64', '3.65'])
    {
        my ($module, $vulnerable, $fixed) = @{$case};
        ok(!$requirements->accepts_module($module, $vulnerable),
            "$module vulnerable version is excluded from consumer requirements");
        ok(
            $requirements->accepts_module($module, $fixed),
            "$module first accepted fixed version remains installable"
        );
    }
}
ok(
    exists($metas[0]->prereqs->{develop}{requires}{'Perl::Tidy'}),
    'JSON additionally retains author prerequisites unsupported by legacy YAML'
);
my $manifest = maniread();
for my $file (qw(README README.md LICENSE NOTICE SECURITY.md Changes Makefile.PL bin/ham-rtty)) {
    ok(exists($manifest->{$file}) && -s $file, "$file is present in the release inventory");
}
done_testing;
