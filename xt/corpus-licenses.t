use strict;
use warnings;
use Test::More;
use JSON::PP;
use Digest::SHA qw(sha256_hex);
use File::Find  qw(find);

sub bytes {
    my ($path) = @_;
    open my $in, '<:raw', $path or die $!;
    my $data = do { local $/; <$in> };
    close $in or die $!;
    return $data;
}
my $cases = JSON::PP->new->decode(bytes('corpus/real.json'));
is(scalar @{$cases}, 4, 'four required real recording slots');
my %inventory;
for my $case (@{$cases}) {
    $inventory{$case->{file}} = 1;
    is($case->{quality_target_cer}, 0.25, 'quality target unchanged');
    if ($case->{status} eq 'missing') {
        ok(!-f $case->{file}, 'missing placeholder contains no unreviewed recording');
        ok(!defined($case->{max_regression_cer}), 'no invented measured budget');
        next;
    }
    is($case->{status}, 'reviewed', 'recording was reviewed');
    for my $field (qw(source_url license sha256 reference max_regression_cer)) {
        ok(defined($case->{$field}), "recording has $field");
    }
    is(sha256_hex(bytes($case->{file})), $case->{sha256}, 'recording hash');
}
my $free     = JSON::PP->new->decode(bytes('corpus/free.json'));
my %licenses = (
    'CC-BY-4.0'                => 'https://creativecommons.org/licenses/by/4.0/',
    'CC0-1.0'                  => 'https://creativecommons.org/publicdomain/zero/1.0/',
    'LicenseRef-Public-Domain' => 'https://commons.wikimedia.org/wiki/File:RTTY.ogg#Licensing'
);
for my $case (@{$free}) {
    $inventory{$case->{file}} = 1;
    for my $field (
        qw(author title source_url download_url download_sha256 sha256 license license_url license_evidence reference reference_method transformation_commands)
        )
    {
        ok(defined($case->{$field}), "$case->{id} has $field");
    }
    is($case->{license_url}, $licenses{$case->{license}}, 'recognised free recording licence');
    is(sha256_hex(bytes($case->{file})), $case->{sha256}, 'distributed free fixture hash');
    like($case->{download_sha256}, qr/\A[0-9a-f]{64}\z/, 'download hash retained');
    my $credits = bytes($case->{license_evidence});
    like($credits, qr/\Q$case->{source_url}\E/, 'source linked in distributed credits');
    for my $name (split /;\s*replacement\s+by\s+/x, $case->{author}) {
        like($credits, qr/\Q$name\E/, 'creator retained in distributed credits');
    }
    like($case->{reference_method}, qr/not an authoritative/, 'reference limits are explicit');
}
my @audio;
find(sub { push @audio, $File::Find::name if /\.wav\z/x }, 'corpus');
ok($inventory{$_}, "no unreviewed audio: $_") for @audio;
done_testing;
