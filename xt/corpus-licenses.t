use strict;
use warnings;
use Test::More;
use JSON::PP;
use Digest::SHA        qw(sha256_hex);
use ExtUtils::Manifest qw(maniread);

sub read_bytes {
    my ($path) = @_;
    open my $input, '<:raw', $path or die "Cannot read $path: $!";
    local $/;
    my $bytes = <$input>;
    close $input or die $!;
    return $bytes;
}
my $manifest  = maniread();
my $cases     = JSON::PP->new->utf8->decode(read_bytes('corpus/real.json'));
my $evidence  = JSON::PP->new->utf8->decode(read_bytes('corpus/real/license-evidence.json'));
my %by_source = map { ($_->{source_page} => $_) } @{$evidence};
my @reviewed  = ('corpus/sos-650hz-20wpm.wav', map { $_->{file} } @{$cases});
my @distributed_audio = grep { /\.(?:wav|ogg|oga|mp3|flac|aif|aiff|m4a|mid)\z/i } keys %{$manifest};
is_deeply(
    [sort @distributed_audio],
    [sort @reviewed],
    'every distributed audio file is in the reviewed license inventory'
);

for my $notice (
    qw(NOTICE corpus/real/LICENSES.md corpus/real/license-evidence.json
    corpus/real/CC0-1.0.txt corpus/real/CC-BY-SA-3.0.txt)
    )
{
    ok(exists($manifest->{$notice}) && -f $notice, "$notice is shipped");
}
like(read_bytes('corpus/real/CC0-1.0.txt'), qr/CC0 1\.0 Universal/, 'CC0 legal text is present');
like(
    read_bytes('corpus/real/CC-BY-SA-3.0.txt'),
    qr/Attribution-ShareAlike 3\.0 Unported/,
    'BY-SA legal text is present'
);
is(
    sha256_hex(read_bytes('corpus/sos-650hz-20wpm.wav')),
    'c210a7e11819f0481ff374a83738b1709007921463c8faa7c9e3899165fc60cd',
    'original synthetic fixture matches the reviewed project-owned recording'
);
my %reviewed_licenses = ('CC0-1.0' => 'CC0', 'CC-BY-SA-3.0' => 'CC BY-SA 3.0');
for my $case (@{$cases}) {
    my $name = $case->{name};
    ok(
        exists($reviewed_licenses{$case->{license}}),
        "$name has an explicitly reviewed free license"
    );
    ok(length($case->{author} // '') && length($case->{transformation} // ''),
        "$name has attribution and a change description");
    is(sha256_hex(read_bytes($case->{file})),
        $case->{sha256}, "$name matches the reviewed derivative");
    like($case->{source_sha256}, qr/\A[0-9a-f]{64}\z/,
        "$name identifies the original source bytes");
    my $record = $by_source{$case->{source}};
    ok($record, "$name source license evidence is retained");
    next unless $record;
    my @derivatives = grep { $_->{file} eq $case->{file} } @{$record->{derivatives} // []};
    is(scalar(@derivatives), 1, "$name has one pinned derivative record");
    is_deeply(
        $derivatives[0],
        {
            map { ($_ => $case->{$_}) }
                qw(file sha256 source_sha256 start_seconds end_seconds sample_rate reference wpm transformation)
        },
        "$name derivative evidence matches the source crop and transformation"
    );
    is(
        $record->{license_metadata}{LicenseShortName},
        $reviewed_licenses{$case->{license}},
        "$name preserves the publisher's license"
    );
    is($record->{license_metadata}{Restrictions},
        '', "$name source lists no additional restrictions");
    like($record->{license_metadata}{Credit}, qr/Own work/, "$name uploader asserts own work");
    like($record->{license_metadata}{Artist},
        qr/\Q$case->{author}\E/, "$name author matches source");
    like($record->{source_permalink},
        qr/[?&]oldid=\d+\z/, "$name evidence pins a source page revision");
}
ok(!exists $manifest->{'corpus/morse.wav'}, 'unverified local recording is not distributed');
done_testing;
