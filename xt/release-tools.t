use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use File::Path qw(make_path);
use File::Spec;
use File::Find qw(find);
use IPC::Open3 qw(open3);
use Symbol     qw(gensym);
use Archive::Tar;
use JSON::PP;
use Cwd         qw(getcwd);
use Digest::SHA qw(sha256_hex);
use Ham::RTTY   ();

sub write_file {
    my ($path, $content) = @_;
    open my $out, '>', $path or die $!;
    print {$out} $content or die $!;
    close $out            or die $!;
    return;
}

sub run {
    my (@arguments) = @_;
    my $error       = gensym();
    my $pid         = open3(undef, my $out, $error, $^X, @arguments);
    my $stdout      = do { local $/; <$out> };
    my $stderr      = do { local $/; <$error> };
    close $out   or die $!;
    close $error or die $!;
    waitpid $pid, 0;
    return ($?, ($stdout // '') . ($stderr // ''));
}

my $temporary = tempdir(CLEANUP => 1);
my $directory = File::Spec->catdir($temporary, 'Ham-RTTY-test');
make_path($directory);
my $manifest = File::Spec->catfile($directory, 'MANIFEST');
my $archive  = File::Spec->catfile($temporary, 'release.tar');
write_file($manifest, "MANIFEST\nmissing.pm\n");
my ($status, $output) = run('maint/archive.pl', $archive, $directory);
isnt($status, 0, 'missing manifest entry fails archive construction');
like($output, qr/Missing or unreadable distribution file/, 'failure identifies incomplete input');
ok(!-e $archive, 'incomplete distribution is not written');
write_file(File::Spec->catfile($directory, 'module.pm'), "package Sample; 1;\n");
write_file($manifest,                                    "MANIFEST\nmodule.pm\n");
($status, $output) = run('maint/archive.pl', $archive, $directory);
is($status, 0, 'complete distribution builds') or diag($output);
my $tar = Archive::Tar->new($archive);
is(scalar($tar->list_files), 2, 'archive includes every manifest entry');
unlink $archive or die $!;
write_file($manifest, '');
($status, $output) = run('maint/archive.pl', $archive, $directory);
isnt($status, 0, 'empty manifest fails archive construction');
unlink $manifest or die $!;
($status, $output) = run('maint/archive.pl', $archive, $directory);
isnt($status, 0, 'absent manifest fails archive construction');

# The coverage database double reports 100% for any requested subset.
# The gate must independently verify the complete source inventory.
my $modules = File::Spec->catdir($temporary, 'Devel', 'Cover');
make_path($modules);
write_file(File::Spec->catfile($modules, 'DB.pm'), <<'DATABASE');
package Devel::Cover::DB;
use strict;
use warnings;
sub new { return bless {}, shift }
sub merge_runs { return $_[0] }
sub cover { return $_[0] }
sub items { return split /\n/, $ENV{HAM_RTTY_TEST_COVER_ITEMS} }
sub calculate_summary { return }
sub summary { return {statement => {percentage => 100}, branch => {percentage => 100}} }
1;
DATABASE
my @files;
find(
    {
        no_chdir => 1,
        wanted   => sub {
            push @files, $File::Find::name if /\.pm\z/x && -f $_;
        }
    },
    'lib'
);
for my $case (
    ['partial',   ['lib/Ham/RTTY/Error.pm'], qr/Missing production module coverage/],
    ['duplicate', [@files, 'blib/lib/Ham/RTTY/Error.pm'], qr/Duplicate production coverage/],
    ['unknown',   [@files, 'lib/Ham/RTTY/Unshipped.pm'],  qr/Unexpected production coverage/]
    )
{
    local $ENV{HAM_RTTY_TEST_COVER_ITEMS} = join "\n", @{$case->[1]};
    ($status, $output) = run("-I$temporary", 'maint/coverage.pl', 'test-db');
    isnt($status, 0, "$case->[0] coverage cannot pass with a 100% subset");
    like($output, $case->[2], "$case->[0] coverage explains failure");
}
{
    local $ENV{HAM_RTTY_TEST_COVER_ITEMS} = join "\n", @files;
    ($status, $output) = run("-I$temporary", 'maint/coverage.pl', 'test-db');
    is($status, 0, 'complete source coverage passes') or diag($output);
    like($output, qr/"percentage"\s*:\s*100/x, 'complete coverage summary is reported');
}
{
    local $ENV{HAM_RTTY_TEST_COVER_ITEMS} = join "\n",
        map { "C:\\checkout\\blib\\$_" =~ tr{/}{\\}r } @files;
    ($status, $output) = run("-I$temporary", 'maint/coverage.pl', 'test-db');
    is($status, 0, 'absolute Windows blib paths map to the production inventory') or diag($output);
}

# Check actual release bytes, including a metadata mismatch that basic archive
# indicators can miss. make distmeta supplies the candidate staging directory.
my $staging       = "Ham-RTTY-$Ham::RTTY::VERSION";
my $candidate     = File::Spec->catfile($temporary, "Ham-RTTY-$Ham::RTTY::VERSION.tar.gz");
my $candidate_raw = File::Spec->catfile($temporary, "Ham-RTTY-$Ham::RTTY::VERSION.tar");
($status, $output) = run('maint/archive.pl', $candidate_raw, $staging);
is($status, 0, 'candidate archive is built from the release inventory') or diag($output);
my $release_tar = Archive::Tar->new($candidate_raw);
$release_tar->write($candidate, 1) or die 'Cannot compress candidate archive';
($status, $output) = run('maint/check-dist.pl', $candidate);
is($status, 0, 'candidate passes archive indicators and release contract') or diag($output);
my $candidate_tar  = Archive::Tar->new($candidate);
my $meta_path      = "$staging/META.json";
my $candidate_meta = decode_json($candidate_tar->get_content($meta_path));
$candidate_meta->{provides}{'Ham::RTTY'}{version} = '999.999';
$candidate_tar->replace_content($meta_path, JSON::PP->new->canonical->encode($candidate_meta));
$candidate_tar->write($candidate, 1) or die 'Cannot write metadata mismatch fixture';
($status, $output) = run('maint/check-dist.pl', $candidate);
isnt($status, 0, 'archive rejects an indexed version that differs from its module');
like(
    $output,
    qr/Failed release contract:.*indexed_version:Ham::RTTY/s,
    'mismatch identifies the package that PAUSE would index incorrectly'
);

# Gate fixtures are synthetic test doubles, never entries in the real corpus.
my $checkout    = getcwd();
my $gate_script = File::Spec->catfile($checkout, 'maint', 'reception-corpus.pl');
my $gate_lib    = File::Spec->catdir($checkout,  'lib');
my $gate_root   = File::Spec->catdir($temporary, 'corpus-gate');
make_path(File::Spec->catdir($gate_root, 'corpus'));
chdir $gate_root or die $!;
my @reviewed;

for my $index (0 .. 3) {
    my $name  = "case-$index.wav";
    my $bytes = Ham::RTTY->new(sample_rate => 8000, baud => 50)->wav_bytes("CQ $index");
    open my $wav, '>:raw', $name or die $!;
    print {$wav} $bytes or die $!;
    close $wav          or die $!;
    push @reviewed,
        {
        id                 => "case-$index",
        file               => $name,
        status             => 'reviewed',
        source_url         => 'https://example.invalid/test-double',
        license            => 'CC0-1.0',
        sha256             => sha256_hex($bytes),
        reference          => "CQ $index",
        max_regression_cer => 0,
        quality_target_cer => 0.25,
        baud               => 50,
        shift              => 170
        };
}
my $baseline = JSON::PP->new->encode(\@reviewed);
write_file('corpus/real.json', $baseline);
($status, $output) = run("-I$gate_lib", $gate_script);
is($status, 0, 'gate accepts four distinct complete test doubles') or diag($output);
for my $invalid (
    ['empty reference', sub { $_[0][0]{reference}          = '' },          qr/Missing provenance/],
    ['empty licence',   sub { $_[0][0]{license}            = '' },          qr/Missing provenance/],
    ['empty source',    sub { $_[0][0]{source_url}         = '' },          qr/Missing provenance/],
    ['invalid URL',     sub { $_[0][0]{source_url}         = 'not-a-url' }, qr/Invalid source URL/],
    ['duplicate ID',    sub { $_[0][1]{id}                 = $_[0][0]{id} },     qr/Duplicate/],
    ['duplicate file',  sub { $_[0][1]{file}               = $_[0][0]{file} },   qr/Duplicate/],
    ['duplicate hash',  sub { $_[0][1]{sha256}             = $_[0][0]{sha256} }, qr/Duplicate/],
    ['invalid budget',  sub { $_[0][0]{max_regression_cer} = 0.3 }, qr/max_regression_cer/],
    ['weakened target', sub { $_[0][0]{quality_target_cer} = 0.5 }, qr/quality_target_cer/],
    ['missing cases',   sub { pop @{$_[0]} }, qr/exactly four/]
    )
{
    my $cases = JSON::PP->new->decode($baseline);
    $invalid->[1]->($cases);
    write_file('corpus/real.json', JSON::PP->new->encode($cases));
    ($status, $output) = run("-I$gate_lib", $gate_script);
    isnt($status, 0, "$invalid->[0] cannot pass reception gate");
    like($output, $invalid->[2], 'gate explains rejection');
}
for my $silence ([], [(0) x 8000]) {
    my $bytes = '';
    open my $wav, '>:raw', \$bytes or die $!;
    Ham::RTTY::Audio->new->write($wav, $silence, sample_rate => 8000);
    close $wav or die $!;
    open my $out, '>:raw', 'empty.wav' or die $!;
    print {$out} $bytes or die $!;
    close $out          or die $!;
    my $cases = JSON::PP->new->decode($baseline);
    $cases->[0]{file}   = 'empty.wav';
    $cases->[0]{sha256} = sha256_hex($bytes);
    write_file('corpus/real.json', JSON::PP->new->encode($cases));
    ($status, $output) = run("-I$gate_lib", $gate_script);
    isnt($status, 0, 'empty or silent audio cannot pass gate');
    like(
        $output,
        qr/Empty real RTTY recording|No signal in real RTTY recording/,
        'silence rejection is explicit'
    );
}
chdir $checkout or die $!;

done_testing;
