use strict;
use warnings;
use Test::More;
use Ham::RTTY;
use lib 't/lib';
use Reference qw(reference_sos);

for my $preference (0, 1) {
    my $d = Ham::RTTY::Decoder->new(prefer_prosigns => $preference);
    is($d->decode('-.-.-'), '<CT>', 'ITU starting signal uses CT');
    is($d->decode('...-.'), '<SN>', 'ITU understood signal uses SN');
    is($d->decode('.-.-.'), $preference ? '<AR>' : '+',
        'punctuation preference remains meaningful');
    my $events = Ham::RTTY->new->events('<CT> <SN>');
    $d->feed($events);
    is($d->finish->text, '<CT> <SN>', 'event decoding uses the same ITU signals');
}
my $events = {
    sample_rate => 8000,
    segments    => [
        {state => 'off', samples => 1234},
        {state => 'on',  samples => 480},
        {state => 'off', samples => 9001},
        {state => 'on',  samples => 1440},
        {state => 'off', samples => 83}
    ]
};
my $reference = Ham::RTTY::Generator->new(sample_rate => 8000, frequency => 650)->generate($events);
for my $size (1, 137, 4096) {
    my $next =
        Ham::RTTY::Generator->new(sample_rate => 8000, frequency => 650)->stream($events, $size);
    my @got;
    while (my $block = $next->()) { push @got, @{$block} }
    is_deeply(\@got, $reference, "silence batching preserves phase and boundaries, size $size");
}
is_deeply([@{$reference}[0 .. 1233]], [(0) x 1234], 'leading silence is exactly zero');
my $cyclic = {};
$cyclic->{self} = $cyclic;
my $input   = {unit => 'us', segments => [{state => 'on', duration => 60000, extra => $cyclic}]};
my $decoder = Ham::RTTY::Decoder->new(wpm => 20);
$decoder->feed($input);
$input->{segments}[0]{duration} = 999;
is_deeply(
    $decoder->finish->events->{segments},
    [{state => 'on', duration => 60000}],
    'canonical copy ignores cyclic metadata and isolates caller mutations'
);
delete $cyclic->{self};
{
    no warnings 'redefine';
    local *Ham::RTTY::Encoder::new   = sub { die 'throwaway encoder constructed' };
    local *Ham::RTTY::Generator::new = sub { die 'throwaway generator constructed' };
    ok(Ham::RTTY->new(wpm => 30), 'facade validates configuration without throwaway instances');
    eval { Ham::RTTY->new(wpm => 0) };
    is(ref($@) ? $@->code : "$@",
        'RTTY_E_ARGUMENT', 'shared configuration validator retains argument checks');
}
for my $case ([9, 0, 0, 0, 0], [0, 0, 0, 0, 9]) {
    is(Ham::RTTY::Detector::_robust_peak($case),
        0, 'duplicated edge values do not sustain an impulse');
}
for my $case ([9, 9, 9, 0, 0], [0, 0, 9, 9, 9], [7]) {
    is(
        Ham::RTTY::Detector::_robust_peak($case),
        $case->[-1] || $case->[0],
        'supported endpoint peak is retained'
    );
}
my @edge = ((0) x 4000, @{reference_sos(amplitude => 0.1)});
$edge[$_] = sin(2 * 3.14159265358979 * 650 * $_ / 8000) for 0 .. 39;
like(Ham::RTTY->new->decode_samples(\@edge, sample_rate => 8000, frequency => 650, wpm => 20)->text,
    qr/SOS\z/, 'boundary impulse does not hide the later weak message');
my @backends = ('perl');
push @backends, 'pdl' if eval { require Ham::RTTY::_Internal::PDL; 1 };
for my $backend (@backends) {
    my $detector = Ham::RTTY::Detector->new(sample_rate => 8000, backend => $backend, wpm => 20);
    my $signal   = reference_sos();
    $detector->feed([@{$signal}[0 .. 2000]]);
    my $preview = $detector->result;
    $detector->feed([@{$signal}[2001 .. $#{$signal}]]);
    my @sum = (0) x @{$detector->{frequencies}};
    for my $frame (@{$detector->{frames}}) {
        $sum[$_] += $frame->{powers}[$_] for 0 .. $#sum;
    }
    is_deeply($detector->{tone_totals}, \@sum,
        "$backend cached energy equals recording-order sums");
    is($detector->finish->text, 'SOS', "$backend previews preserve final decoding");
    $detector->reset;
    is_deeply($detector->{tone_totals}, [(0) x @sum], "$backend reset clears candidate energy");

    # Independent per-tone filtering rejects the stronger unkeyed carrier.
    my @two = map { $signal->[$_] * 0.1 + 0.7 * sin(2 * 3.14159265358979 * 1200 * $_ / 8000) }
        0 .. $#{$signal};
    $detector->feed(\@two);
    my $blocked = $detector->finish;
    is($blocked->text,                'SOS', "$backend weaker CW survives a stronger carrier");
    is(scalar @{$detector->channels}, 1,     'unkeyed carrier is not reported as a station');
    my $hinted = Ham::RTTY::Detector->new(
        sample_rate => 8000,
        frequency   => 650,
        wpm         => 20,
        backend     => $backend
    );
    $hinted->feed(\@two);
    is($hinted->finish->text, 'SOS', "$backend known tone is isolated from the stronger carrier");
}

for my $excluded ('!', '&', ';', '_', '$') {
    eval { Ham::RTTY->new->encode($excluded) };
    is(ref($@) ? $@->code : "$@", 'RTTY_E_SYMBOL', 'non-ITU text extension is explicitly excluded');
}
my $validated_config = Ham::RTTY::Encoder->validate(wpm => 30);
is($validated_config->{effective_wpm}, 30, 'public validation resolves encoding defaults');
$validated_config->{wpm} = 99;
is(Ham::RTTY::Encoder->validate(wpm => 30)->{wpm}, 30, 'validation configurations are independent');
my $tone_config = Ham::RTTY::Generator->validate(sample_rate => 1000);
is($tone_config->{frequency}, 250, 'public validation resolves rate-dependent tone default');

# Independent, deliberately uneven keying: no library encoder/generator.
my @schedule = (
    [0, 3], [1, 1], [0, 1], [1, 1], [0, 1], [1, 1], [0, 3], [1, 3], [0, 1], [1, 3],
    [0, 1], [1, 3], [0, 3], [1, 1], [0, 1], [1, 1], [0, 1], [1, 1], [0, 3]
);
my (@manual, $position);
$position = 0;
for my $i (0 .. $#schedule) {
    my $run   = $schedule[$i];
    my $count = int(480 * $run->[1] * (1 + ($i % 5 - 2) * 0.06) + 0.5);
    push @manual,
        map { $run->[0] * 0.6 * sin(2 * 3.14159265358979 * 650 * $position++ / 8000) } 1 .. $count;
}
is(
    Ham::RTTY->new->decode_samples(\@manual, sample_rate => 8000, frequency => 650, wpm => 20)->text,
    'SOS',
    'independent irregular keying remains readable'
);
done_testing;
