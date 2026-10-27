use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use File::Spec;
use CPAN::Meta;
use CPAN::Audit;

require './maint/audit-dependencies.pl';

my $temporary = tempdir(CLEANUP => 1);
my $module    = File::Spec->catfile($temporary, 'Fixture.pm');

sub write_text {
    my ($path, $text) = @_;
    open my $out, '>', $path or die $!;
    print {$out} $text or die $!;
    close $out         or die $!;
    return;
}

write_text($module, "package Fixture v1.2.3;\nBEGIN { die 'Source must not execute' }\n1;\n");
is(module_name($module), 'Fixture', 'version-bearing package yields only the module name');
write_text($module, "package Fixture 1.23 {\n1;\n}\n");
is(module_name($module), 'Fixture', 'block package declarations are inventoried');
write_text(
    $module, q{=pod
package Pretend;
=cut
my $note = 'package String;';
package Fixture;
our $VERSION = do { die 'Version expression must not execute' };
1;
}
);
is(module_name($module), 'Fixture',
    'POD, strings and version expressions do not alter static package inventory');
write_text($module, "package Fixture v1.2.3;\nBEGIN { die 'Source must not execute' }\n1;\n");

my $database = {
    module2dist => {
        Fixture               => 'Fixture',
        Fcntl                 => 'perl',
        'ExtUtils::MakeMaker' => 'ExtUtils-MakeMaker',
        Alias                 => 'Fixture',
    },
    dists => {
        Fixture => {
            main_module => 'Fixture',
            versions    => [{version => 'v1.2.3'}, {version => 'v2.0.0'}],
            advisories  => [
                {
                    id                => 'TEST-OLD',
                    affected_versions => ['<v2.0.0'],
                    fixed_versions    => ['>=v2.0.0']
                }
            ],
        },
        perl                 => {main_module => 'perl', versions => [], advisories => []},
        'ExtUtils-MakeMaker' =>
            {main_module => 'ExtUtils::MakeMaker', versions => [], advisories => []},
    },
};
my $audit      = CPAN::Audit->new(db => $database, no_corelist => 1);
my $vulnerable = installed_report($audit, $temporary);
is($vulnerable->{meta}{total_advisories}, 1, 'installed vulnerable version is detected');
is_deeply($vulnerable->{errors}, [], 'inventory fixture has no scanner errors');
write_text($module, "package Fixture v2.0.0;\n1;\n");
is(installed_report($audit, $temporary)->{meta}{total_advisories},
    0, 'fixed installed version clears its advisory');
write_text($module, "package Fixture v1.2.3;\n1;\n");
is(installed_report($audit, $temporary)->{meta}{total_advisories},
    1, 'downgrade makes the audit red again');

sub metadata {
    my ($prereqs) = @_;
    return CPAN::Meta->new(
        {
            name           => 'Audit-Fixture',
            version        => '0.001',
            abstract       => 'Audit test',
            author         => ['Test'],
            license        => ['perl_5'],
            release_status => 'stable',
            'meta-spec'    => {version => 2},
            dynamic_config => 0,
            generated_by   => 'test',
            prereqs        => $prereqs,
        }
    );
}
my $meta = metadata(
    {
        runtime => {
            requires   => {perl     => '5.020', Fcntl => 0, Fixture => 'v1.2.3'},
            recommends => {Unmapped => 1, Fixture => 'v2.0.0'}
        },
        configure => {requires => {'ExtUtils::MakeMaker' => '7.22'}},
        build     => {requires => {'ExtUtils::MakeMaker' => 0}},
        develop   => {requires => {Fixture               => 'v2.0.0'}},
    }
);
my $scopes = declared_ranges($meta, $database);
my %scopes = map { ($_->{phase} . '/' . $_->{relation} => $_) } @{$scopes};
is($scopes{'runtime/requires'}{ranges}{perl}, '5.020',
    'core aliases cannot overwrite Perl minimum');
is($scopes{'configure/requires'}{ranges}{'ExtUtils-MakeMaker'},
    '7.22', 'configure minimum retained');
is($scopes{'build/requires'}{ranges}{'ExtUtils-MakeMaker'}, '0', 'separate build scope retained');
is($scopes{'runtime/requires'}{ranges}{Fixture},
    'v1.2.3', 'runtime range is not hidden by author minimum');
is($scopes{'develop/requires'}{ranges}{Fixture}, 'v2.0.0', 'author range retained separately');
is_deeply($scopes{'runtime/recommends'}{unmapped_modules},
    ['Unmapped'], 'mapping gap retained in its scope');

my $path = File::Spec->catfile($temporary, 'META.json');
$meta->save($path);
is(declared_report($path, $database)->{meta}{total_advisories},
    1, 'author upgrade cannot hide a vulnerable runtime range');
metadata({runtime => {requires => {perl => '5.020', Fixture => 'v2.0.0'}}})->save($path);
is(declared_report($path, $database)->{meta}{total_advisories},
    0, 'fixed runtime requirement passes');
metadata({runtime => {requires => {perl => '5.020', Fixture => 'v1.2.3'}}})->save($path);
is(declared_report($path, $database)->{meta}{total_advisories},
    1, 'vulnerable permitted versions fail declared audit');

for my $case (
    [{runtime => {requires => {Fixture => 0}}}, qr/Missing explicit Perl/],
    [{runtime => {requires => {perl => '5.020', Fcntl => 1}}}, qr/nonzero core-module/],
    [{runtime => {requires => {perl => '5.020', Alias => 1}}}, qr/module version to distribution/],
    [
        {runtime => {requires => {perl => '5.020'}, suggests => {Fixture => 0}}},
        qr/Unsupported prerequisite relation/
    ]
    )
{
    my $ok = eval { declared_ranges(metadata($case->[0]), $database); 1 };
    ok(!$ok, 'unrepresentable constraints cannot pass silently');
    like($@, $case->[1], 'unsupported input identifies the missing audit model');
}
{
    local *CPANSA::DB::db = sub { return $database };
    local @INC            = ($temporary);
    local @ARGV           = ('installed');
    local *STDOUT;
    my $output = '';
    open STDOUT, '>', \$output or die $!;
    $database->{dists}{Fixture}{advisories}[0]{description} = "non-ASCII: \x{a0}\x{2192}";
    my $status = main();
    close STDOUT or die $!;
    my $report = JSON::PP->new->utf8->decode($output);
    is($status, 1, 'CLI audit remains nonzero for a vulnerable installed package');
    is($report->{meta}{total_advisories}, 1, 'corrected report retains the vulnerable package');
    is($report->{stock_report}{meta}{total_advisories},
        0, 'original discovery miss is retained as evidence');
    is(
        $report->{dists}{Fixture}{advisories}[0]{description},
        "non-ASCII: \x{a0}\x{2192}",
        'JSON artifact preserves Latin-1 and wide Unicode descriptions as UTF-8'
    );
}
done_testing;
