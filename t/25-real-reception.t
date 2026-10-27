use strict;
use warnings;
use Test::More;
use JSON::PP;
use Digest::SHA qw(sha256_hex);
use Ham::RTTY;
use lib 't/lib';
use CorpusMetrics qw(character_error_rate);

is(character_error_rate('SOS', 'SOS'), 0, 'CER exact transcription');
cmp_ok(abs(character_error_rate('SOS', 'SXS') - 1 / 3),  '<', 1e-12, 'CER substitution');
cmp_ok(abs(character_error_rate('SOS', 'SS') - 1 / 3),   '<', 1e-12, 'CER deletion');
cmp_ok(abs(character_error_rate('SOS', 'SOOS') - 1 / 3), '<', 1e-12, 'CER insertion');
is(character_error_rate('A', 'AAAA'), 3, 'CER can exceed one with insertions');
open my $input, '<:raw', 'corpus/real.json' or die $!;
my $cases = JSON::PP->new->decode(do { local $/; <$input> });
close $input or die $!;
my @backends = ('perl');
push @backends, 'pdl' if eval { require Ham::RTTY::_Internal::PDL; 1 };

my %observed;
for my $case (@{$cases}) {
    open my $audio, '<:raw', $case->{file} or die $!;
    my $bytes = do { local $/; <$audio> };
    close $audio or die $!;
    is(sha256_hex($bytes), $case->{sha256},
        "$case->{name} fixture matches attributed source derivative");
    open my $header, '<:raw', \$bytes or die $!;
    my $info = Ham::RTTY::Audio->new->reader($header);
    close $header or die $!;
    is(
        $info->{sample_count},
        int(($case->{end_seconds} - $case->{start_seconds}) * $case->{sample_rate} + 0.5),
        "$case->{name} sample count matches its source crop"
    );
    is($info->{sample_rate}, $case->{sample_rate},
        "$case->{name} retains the documented sample rate");

    for my $backend (@backends) {
        my $cw        = Ham::RTTY->new(backend => $backend);
        my $hinted    = $cw->decode_wav_bytes($bytes, wpm => $case->{wpm});
        my $estimated = $cw->decode_wav_bytes($bytes);
        my %results   = (hinted => $hinted, estimated => $estimated);
        my %cer;
        for my $mode (qw(hinted estimated)) {
            my $result = $results{$mode};
            $cer{$mode} = character_error_rate($case->{reference}, $result->text);
            cmp_ok(
                $cer{$mode}, '<=',
                $case->{"max_regression_cer_$mode"} + 1e-12,
                "$case->{name} / $backend / $mode respects its measured CER budget"
            ) or diag('Decoded: ' . $result->text);
            is(
                $result->diagnostics->{timing_source},
                $mode eq 'hinted' ? 'configured' : 'estimated',
                'unassisted run does not inherit a WPM hint'
            );
            ok($result->complete, 'real clip completes in both speed modes');
        }
        note(
            sprintf(
                '%s / %s: hinted CER %.3f; estimated CER %.3f (%.2f WPM); quality target %.2f',
                $case->{name},   $backend,             $cer{hinted},
                $cer{estimated}, $estimated->wpm // 0, $case->{quality_target_cer}
            )
        );
        $observed{$case->{name}} = {
            cer_hinted     => $cer{hinted},
            cer_estimated  => $cer{estimated},
            text_estimated => $estimated->text,
            estimated_wpm  => $estimated->wpm
            }
            if $backend eq 'perl';
    }
}
open my $report, '-|', $^X, '-Mwarnings=FATAL,all', 'maint/reception-corpus.pl' or die $!;
my $bytes = do { local $/; <$report> };
ok(close($report), 'corpus reporting command succeeds');
my $rows = JSON::PP->new->utf8->decode($bytes);
is(scalar(@{$rows}), scalar(@{$cases}), 'report retains one row per real clip');
for my $row (@{$rows}) {
    is_deeply(
        {map { ($_ => $row->{$_}) } qw(cer_hinted cer_estimated text_estimated estimated_wpm)},
        $observed{$row->{name}},
        "$row->{name} report contains independently estimated results"
    );
}
done_testing;
