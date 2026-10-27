use strict;
use warnings;
use Test::More;
use JSON::PP;
use Ham::RTTY;
open my $json, '<:raw', 'corpus/vectors.json' or die $!;
my $bytes = do { local $/; <$json> };
close $json or die $!;
my $vectors = JSON::PP->new->decode($bytes);
my $cw      = Ham::RTTY->new;

for my $vector (@{$vectors}) {
    is($cw->encode($vector->{text}),  $vector->{morse}, 'fixed corpus encode');
    is($cw->decode($vector->{morse}), $vector->{text},  'fixed corpus decode');
}
open my $wav, '<:raw', 'corpus/sos-650hz-20wpm.wav' or die $!;
my $result = $cw->decode_wav($wav);
is($result->text,                            'SOS', 'independently produced WAV fixture');
is($result->frequency,                       650,   'fixture tone');
is($result->diagnostics->{analyzed_samples}, 15840, 'fixture duration');
done_testing;
