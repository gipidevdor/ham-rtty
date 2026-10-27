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
my @audio;
find(sub { push @audio, $File::Find::name if /\.wav\z/x }, 'corpus');
ok($inventory{$_}, "no unreviewed audio: $_") for @audio;
done_testing;
