use 5.020;
use strict;
use warnings FATAL => 'all';
use Test::More;
use Ham::RTTY::Encoder;
use Ham::RTTY::Generator;
my $events = Ham::RTTY::Encoder->new->events('CQ 123');
my $whole  = Ham::RTTY::Generator->new->generate($events);

for my $size (1, 137, 4096) {
    my $gen  = Ham::RTTY::Generator->new;
    my $next = $gen->stream($events, $size);
    my @samples;
    while (my $block = $next->()) { push @samples, @{$block} }
    is_deeply(\@samples, $whole, "block independent $size");
    is($gen->state, 'FINISHED', 'final state');
    ok(!eval { $gen->generate($events); 1 }, 'reset required');
}
my $gen  = Ham::RTTY::Generator->new;
my $next = $gen->stream($events);
$gen->reset;
ok(!eval { $next->(); 1 }, 'old iterator invalidated');
my $phase = 0;
my $pi    = 4 * atan2(1, 1);
my $exact = {
    sample_rate => 8000,
    segments    => [
        {state => 'mark',  samples => 10},
        {state => 'space', samples => 11},
        {state => 'mark',  samples => 12}
    ]
};
my $samples = Ham::RTTY::Generator->new(sample_rate => 8000)->generate($exact);
my $i       = 0;

for my $run (@{$exact->{segments}}) {
    my $f = $run->{state} eq 'mark' ? 2125 : 2295;
    for (1 .. $run->{samples}) {
        cmp_ok(abs($samples->[$i++] - 0.8 * sin($phase)),
            '<', 1e-12, 'independent phase accumulator');
        $phase += 2 * $pi * $f / 8000;
        $phase -= 2 * $pi if $phase >= 2 * $pi;
    }
}
for my $args (
    [sample_rate => 4000],
    [mark        => 2900, shift => 170],
    [reverse     => 2],
    [max_samples => 0],
    [amplitude   => 2],
    [backend     => 'bad']
    )
{
    ok(!eval { Ham::RTTY::Generator->new(@{$args}); 1 }, 'invalid generation settings');
}
ok(!eval { Ham::RTTY::Generator->new(max_samples => 1)->generate($events); 1 }, 'resource ceiling');
done_testing;
