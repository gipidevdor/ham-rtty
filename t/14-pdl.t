use 5.020;
use strict;
use warnings FATAL => 'all';
use Test::More;
use Ham::RTTY;
use Ham::RTTY::_Internal::Backend;
plan skip_all => 'PDL 2.081 is optional'
    unless Ham::RTTY::_Internal::Backend::resolve('auto') eq 'pdl';
my $rtty   = Ham::RTTY->new;
my $events = $rtty->events('CQ 123 73');
my $whole  = $rtty->generator(backend => 'pdl')->generate($events);

for my $size (1, 137, 4096) {
    my $next = $rtty->generator(backend => 'pdl')->stream($events, $size);
    my @values;
    while (my $block = $next->()) { push @values, @{$block} }
    is_deeply(\@values, $whole, "PDL waveform block independence $size");
}
my $pure = $rtty->generator(backend => 'perl')->generate($events);
my $max  = 0;
for my $i (0 .. $#{$pure}) { my $d = abs($pure->[$i] - $whole->[$i]); $max = $d if $d > $max }
cmp_ok($max, '<', 1e-10, 'backend waveform tolerance');
for my $bits (8, 16, 24) {
    is(
        $rtty->decode_wav_bytes($rtty->wav_bytes('CQ 123', bits => $bits, backend => 'pdl'),
            backend => 'pdl')->text,
        'CQ 123',
        "PDL PCM $bits"
    );
}
done_testing;
