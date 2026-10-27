use strict;
use warnings;
use Test::More;
use lib 't/lib';
use Reference qw(reference_sos);
use Ham::RTTY;

sub decode_signal {
    my ($samples, %args) = @_;
    my $d = Ham::RTTY::Detector->new(sample_rate => 8000, frequency => 650, wpm => 20, %args);
    $d->feed($samples);
    return $d->finish;
}
my $pi  = 4 * atan2(1, 1);
my @one = (0) x 400;
push @one, map { 0.6 * sin(2 * $pi * 650 * $_ / 8000) } 0 .. 479;
push @one, (0) x 400;
is(decode_signal(\@one)->text, '', 'isolated mark is not identified as CW');
my $cw =
    Ham::RTTY->new(wpm => 20, sample_rate => 8000, frequency => 650, attack_ms => 0, release_ms => 0);
my $bad = {sample_rate => 8000, segments => []};

for (1 .. 4) {
    push @{$bad->{segments}}, {state => 'on', samples => 880}, {state => 'off', samples => 480};
}
my $invalid =
    Ham::RTTY::Generator->new(sample_rate => 8000, frequency => 650, attack_ms => 0, release_ms => 0)
    ->generate($bad);
my $r = decode_signal($invalid);
is($r->text, "\x{FFFD}", 'invalid group retains replacement character');
ok(grep($_->{code} eq 'RTTY_W_TIMING', @{$r->warnings}), 'timing rejection warning');
my $same =
    Ham::RTTY::Generator->new(sample_rate => 8000, frequency => 650)->generate($cw->events('SSS'));
my $auto = Ham::RTTY::Detector->new(sample_rate => 8000, frequency => 650);
$auto->feed($same);
is($auto->finish->text, '', 'single mark length needs WPM hint');
my $signal = reference_sos();
my @rising = map { $signal->[$_] * (0.1 + 0.9 * $_ / $#{$signal}) } 0 .. $#{$signal};
is(decode_signal(\@rising)->text, 'SOS', 'adaptive envelope follows a rising signal level');

# A 5 ms tone burst during a word/letter gap must not become an extra mark.
for my $i (3000 .. 3039) { $signal->[$i] = 0.9 * sin(2 * $pi * 650 * $i / 8000) }
is(decode_signal($signal)->text, 'SOS', 'short keyed-band impulse is removed');
my $d =
    Ham::RTTY::Detector->new(sample_rate => 8000, frequency => 650, wpm => 20, effective_wpm => 20);
$d->feed([@{$signal}[0 .. 4999]]);
ok(!$d->result->complete, 'intermediate snapshot is provisional');
$d->feed([@{$signal}[5000 .. $#{$signal}]]);
is($d->finish->text, 'SOS', 'snapshot does not consume state');
my $partial = reference_sos();
push @{$partial}, (0) x 7;
my $p = decode_signal($partial);
is($p->diagnostics->{analyzed_samples}, scalar @{$partial}, 'partial final frame counted');
my $rate11025 = reference_sos(rate => 11025, frequency => 700);
my $other     = Ham::RTTY::Detector->new(sample_rate => 11025, frequency => 700, wpm => 20);
$other->feed($rate11025);
is($other->finish->text, 'SOS', 'non-divisible sample rate');
my $low_rate = Ham::RTTY::Detector->new(sample_rate => 1000, frequency => 200, wpm => 20);
$low_rate->feed(reference_sos(rate => 1000, frequency => 200));
is($low_rate->finish->text, 'SOS', 'known tone at the lowest supported sample rate');
eval {
    Ham::RTTY::Detector->new(
        sample_rate    => 16000,
        min_frequency  => 1,
        max_frequency  => 7999,
        frequency_step => 10
    );
};
is((ref($@) ? $@->code : "$@"), 'RTTY_E_RESOURCE', 'frequency candidate resource limit');
my $snapshot = Ham::RTTY::Result->new(warnings => [{code => 'RTTY_W_TEST', message => 'sample'}]);
my $warnings = $snapshot->warnings;
$warnings->[0]{code} = 'BAD';
is($snapshot->warnings->[0]{code}, 'RTTY_W_TEST', 'warning snapshot deep copy');
done_testing;
