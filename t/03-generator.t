use strict;
use warnings;
use Test::More;
use Ham::RTTY::Generator;
my $events = {
    sample_rate => 16000,
    segments    => [
        {state => 'on',  samples => 1600},
        {state => 'off', samples => 333},
        {state => 'on',  samples => 1600}
    ]
};
my %opts  = (frequency => 700, attack_ms => 0, release_ms => 0);
my $whole = Ham::RTTY::Generator->new(%opts)->generate($events);
is(scalar @{$whole}, 3533, 'exact duration');
my $pi = 4 * atan2(1, 1);
cmp_ok(abs($whole->[200] - 0.8 * sin(2 * $pi * 700 * 200 / 16000)),
    '<', 1e-12, 'analytic oscillator value');
cmp_ok(abs($whole->[2000] - 0.8 * sin(2 * $pi * 700 * 2000 / 16000)),
    '<', 1e-12, 'phase advances through silence');
my $max = 0;
for (@{$whole}) { $max = abs($_) if abs($_) > $max }
cmp_ok($max, '<=', 0.8, 'amplitude bound');
my $crossings = 0;
for my $i (1 .. 1599) { ++$crossings if $whole->[$i - 1] <= 0 && $whole->[$i] > 0 }
is($crossings, 70, 'independent zero-crossing frequency check');

for my $size (1, 7, 80, 257, 4096) {
    my $g    = Ham::RTTY::Generator->new(%opts);
    my $next = $g->stream($events, $size);
    my @got;
    while (my $block = $next->()) { push @got, @{$block} }
    is_deeply(\@got, $whole, "identical samples in blocks of $size");
    is($g->state, 'FINISHED', 'iterator lifecycle');
    eval { $g->generate($events) };
    is((ref($@) ? $@->code : "$@"), 'RTTY_E_STATE', 'reset required');
    $g->reset;
    is($g->state, 'READY', 'reset');
}
my $shaped = Ham::RTTY::Generator->new->generate($events);
is($shaped->[0],    0, 'attack starts at zero');
is($shaped->[1599], 0, 'release ends at zero');
my $tiny = Ham::RTTY::Generator->new->generate(
    {sample_rate => 16000, segments => [{state => 'on', samples => 2}]});
is_deeply($tiny, [0, 0], 'short envelopes stay within mark');
my $g    = Ham::RTTY::Generator->new;
my $next = $g->stream($events);
$g->reset;
eval { $next->() };
is((ref($@) ? $@->code : "$@"), 'RTTY_E_STATE', 'old stream invalidated');
eval { Ham::RTTY::Generator->new(max_samples => 10)->generate($events) };
is((ref($@) ? $@->code : "$@"), 'RTTY_E_RESOURCE', 'generation limit');

for my $args (
    {frequency   => 8000},
    {amplitude   => 1.01},
    {sample_rate =>  1},
    {attack_ms   => -1},
    {unknown     => 1}
    )
{
    eval { Ham::RTTY::Generator->new(%{$args}) };
    is((ref($@) ? $@->code : "$@"), 'RTTY_E_ARGUMENT', 'validate synthesis options');
}
done_testing;
