use strict;
use warnings;
use Test::More;
use lib 't/lib';
use Reference qw(reference_sos noise);
use Ham::RTTY::Detector;

sub detect {
    my ($samples, %args) = @_;
    my $d = Ham::RTTY::Detector->new(sample_rate => 8000, %args);
    $d->feed($samples);
    return $d->finish;
}
for my $frequency (350, 650, 1000, 1450) {
    my $r = detect(reference_sos(frequency => $frequency));
    is($r->text, 'SOS', "independent audio at $frequency Hz");
    cmp_ok(abs($r->frequency - $frequency), '<=', 50, 'frequency grid estimate');
    cmp_ok(abs($r->wpm - 20),               '<',  2,  'timing estimate');
}
for my $wpm (5, 12, 30, 45, 60) {
    my $r = detect(reference_sos(wpm => $wpm), frequency => 650, wpm => $wpm);
    is($r->text, 'SOS', "independent audio at $wpm WPM");
}
for my $amplitude (0.01, 0.2, 0.9) {
    is(detect(reference_sos(amplitude => $amplitude), frequency => 650)->text,
        'SOS', "amplitude $amplitude");
}
is(detect(reference_sos(fading => 1), frequency => 650, wpm => 20)->text, 'SOS', 'moderate fading');
is(detect(reference_sos(drift  => 2), frequency => 650, wpm => 20)->text,
    'SOS', 'small frequency variation');
my $clean = reference_sos();
my $noise = noise(scalar @{$clean}, 0.12);
my @noisy = map { $clean->[$_] + $noise->[$_] } 0 .. $#{$clean};
is(detect(\@noisy, frequency => 650, wpm => 20)->text,
    'SOS', 'deterministic white noise at moderate level');
my @impulsive = @{$clean};
for (my $i = 200; $i < @impulsive; $i += 3000) { $impulsive[$i] = 0.99 }
is(detect(\@impulsive, frequency => 650, wpm => 20)->text, 'SOS', 'isolated impulses');

for my $input (
    [],
    [(0) x 8000],
    noise(8000, 0.3),
    [map { 0.5 * sin(2 * 3.14159265358979 * 650 * $_ / 8000) } 0 .. 7999]
    )
{
    my $r = detect($input);
    is($r->text, '', 'no invented text from silence/noise/unkeyed tone');
    ok(@{$r->warnings}, 'rejection diagnostic');
    ok($r->complete,    'finalization is separate from detection');
}
my $d = Ham::RTTY::Detector->new(sample_rate => 8000, frequency => 650, max_frames => 10);
eval { $d->feed([(0) x 401]) };
is((ref($@) ? $@->code : "$@"), 'RTTY_E_RESOURCE', 'bounded feature history');
is($d->state,                   'READY',         'resource validation atomic');
eval { $d->feed([0, 'NaN']) };
is((ref($@) ? $@->code : "$@"), 'RTTY_E_ARGUMENT', 'reject nonfinite input');
is($d->state,                   'READY',         'invalid sample atomic');
$d->feed([(0) x 100]);
$d->finish;
eval { $d->feed([]) };
is((ref($@) ? $@->code : "$@"), 'RTTY_E_STATE', 'post-finish feed');
$d->reset;
is($d->state, 'READY', 'detector reset');
done_testing;
