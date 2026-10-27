use 5.020;
use strict;
use warnings FATAL => 'all';
use Test::More;
use JSON::PP;
use Ham::RTTY;
use Ham::RTTY::_Internal::Backend;
use lib 't/lib';
use CorpusMetrics qw(character_error_rate);
open my $input, '<:raw', 'corpus/free.json' or die $!;
my $cases = JSON::PP->new->decode(do { local $/ = undef; <$input> });
close $input or die $!;
my @backends = ('perl');
push @backends, 'pdl' if Ham::RTTY::_Internal::Backend::resolve('auto') eq 'pdl';

for my $case (@{$cases}) {
    my $expected = $case->{reference};
    $expected =~ s/\r\n?/\n/gx;
    for my $backend (@backends) {
        my $previous;
        for my $block (137, 4096) {
            my $result = Ham::RTTY->new->read_wav(
                $case->{file},
                backend       => $backend,
                block_samples => $block,
                map { $_ => $case->{$_} } qw(baud shift mark)
            );
            my $label = "$case->{id} $backend block $block";
            ok($result->complete && $result->has_text, "$label produces a final nonempty result");
            my $actual = $result->text;
            $actual =~ s/\r\n?/\n/gx;
            cmp_ok(
                character_error_rate($expected, $actual),
                '<=',
                $case->{max_disagreement_rate},
                "$label independent-decoder disagreement budget"
            );
            is($actual, $previous, "$label agrees across input block sizes") if defined $previous;
            $previous = $actual;
        }
    }
}
done_testing;
