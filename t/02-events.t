use strict;
use warnings;
use Test::More;
use Storable qw(dclone);
use Ham::RTTY::Encoder;
use Ham::RTTY::Decoder;
use Ham::RTTY::Events qw(validate_events to_samples to_timed);
for my $wpm (5 .. 60) {
    my $e = Ham::RTTY::Encoder->new(wpm => $wpm)->events('A B');
    is(validate_events($e), 'duration', "canonical at $wpm WPM");
    cmp_ok(abs($e->{segments}[0]{duration} - 1200000 / $wpm), '<=', 0.5, 'dot timing');
    my $d = Ham::RTTY::Decoder->new(wpm => $wpm);
    $d->feed($e);
    is($d->finish->text, 'A B', 'event decode');
}
my $encoder  = Ham::RTTY::Encoder->new(wpm => 20, effective_wpm => 10);
my $p        = $encoder->events('LIGHT LIGHT');
my $duration = 0;
$duration += $_->{duration} for @{$p->{segments}};
my $one   = $encoder->events('LIGHT');
my $first = 0;
$first += $_->{duration} for @{$one->{segments}};
is($duration - $first, 6000000, 'LIGHT Farnsworth word cadence is exactly six seconds');
my $d = Ham::RTTY::Decoder->new(wpm => 20, effective_wpm => 10);
$d->feed($p);
is($d->finish->text, 'LIGHT LIGHT', 'Farnsworth decode');
my $e = {
    unit     => 'us',
    segments => [map { +{state => $_ % 2 ? 'off' : 'on', duration => 33333} } 0 .. 999]
};
my $before = dclone($e);
my $s      = to_samples($e, 11025);
my $n      = 0;
$n += $_->{samples} for @{$s->{segments}};
is($n, 367496, 'cumulative conversion avoids drift');
is_deeply($e, $before, 'conversion does not modify input');
is(validate_events(to_timed($s)), 'duration', 'reverse conversion');
is_deeply(
    to_samples({unit => 'us', segments => []}, 16000),
    {sample_rate => 16000, segments => []},
    'empty conversion'
);

for my $bad (
    {unit => 'ms', segments    => []},
    {unit => 'us', sample_rate => 16000, segments => []},
    {unit => 'us', segments    => [{state => 'on', duration => 0}]},
    {unit => 'us', segments    => [{state => 'on', duration => 1}, {state => 'on', duration => 2}]},
    {sample_rate => 0,    segments => []},
    {unit        => 'us', segments => [{state => 'bad', duration => 1}]},
    {
        unit     => 'us',
        segments => [{state => 'on', duration => 2**52}, {state => 'off', duration => 1}]
    }
    )
{
    eval { validate_events($bad) };
    isa_ok($@, 'Ham::RTTY::Error', 'invalid events');
}
eval { to_samples({unit => 'us', segments => [{state => 'on', duration => 1}]}, 1000) };
is((ref($@) ? $@->code : "$@"), 'RTTY_E_TIMING', 'insufficient resolution rejected');
my $auto = Ham::RTTY::Decoder->new;
$auto->feed(Ham::RTTY::Encoder->new(wpm => 17)->events('CQ TEST'));
is($auto->finish->text, 'CQ TEST', 'estimate timing from mixed marks');
done_testing;
