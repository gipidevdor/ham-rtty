use strict;
use warnings;
use Test::More;
use Ham::RTTY;
use Ham::RTTY::Audio;
use Ham::RTTY::Detector;
use Ham::RTTY::Generator;
use Ham::RTTY::_Internal::Backend;
use lib 't/lib';
use Reference qw(reference_sos noise);

for my $class (qw(Ham::RTTY Ham::RTTY::Audio Ham::RTTY::Generator Ham::RTTY::Detector)) {
    eval { $class->new(backend => 'invalid') };
    is((ref($@) ? $@->code : "$@"), 'RTTY_E_ARGUMENT', "$class validates backend");
}
{
    local $INC{'Ham/RTTY/_Internal/PDL.pm'} = undef;
    is(Ham::RTTY::_Internal::Backend::resolve('auto'), 'perl', 'auto fallback when PDL cannot load');
    eval { Ham::RTTY::_Internal::Backend::resolve('pdl') };
    is((ref($@) ? $@->code : "$@"), 'RTTY_E_ARGUMENT', 'explicit backend load failure');
}
eval { Ham::RTTY::_Internal::Backend::resolve([]) };
is((ref($@) ? $@->code : "$@"), 'RTTY_E_ARGUMENT', 'backend rejects references');
my $pdl = eval { require Ham::RTTY::_Internal::PDL; 1 };
is(Ham::RTTY::_Internal::Backend::resolve('auto'), $pdl ? 'pdl' : 'perl', 'automatic backend');
if (!$pdl) {
    eval { Ham::RTTY->new(backend => 'pdl') };
    is((ref($@) ? $@->code : "$@"), 'RTTY_E_ARGUMENT', 'missing PDL is a structured error');
    done_testing;
    exit;
}
my $events = Ham::RTTY->new->events('SOS');
for my $rate (1000, 8000, 16000, 44100) {
    my %options  = (sample_rate => $rate, frequency => 350, attack_ms => 8, release_ms => 3);
    my $expected = Ham::RTTY::Generator->new(%options)->generate($events);
    for my $size (127, 4096) {
        my $next = Ham::RTTY::Generator->new(%options, backend => 'pdl')->stream($events, $size);
        my @actual;
        while (my $block = $next->()) { push @actual, @{$block} }
        is(scalar @actual, scalar @{$expected}, "sample count $rate / $size");
        my $max = 0;
        for my $i (0 .. $#actual) {
            my $delta = abs($actual[$i] - $expected->[$i]);
            $max = $delta if $delta > $max;
        }
        cmp_ok($max, '<', 1e-10, "waveform equivalence $rate / $size");
    }
}
for my $input (reference_sos(), reference_sos(fading => 1), noise(8000, 0.3), [(0) x 401], []) {
    my $reference = Ham::RTTY::Detector->new(sample_rate => 8000);
    $reference->feed($input);
    my $expected = $reference->finish->as_hash;
    for my $size (17, 4096) {
        my $detector = Ham::RTTY::Detector->new(sample_rate => 8000, backend => 'pdl');
        for (my $i = 0; $i < @{$input}; $i += $size) {
            my $end = $i + $size - 1;
            $end = $#{$input} if $end > $#{$input};
            $detector->feed([@{$input}[$i .. $end]]);
        }
        my $actual = $detector->finish->as_hash;
        is($actual->{text}, $expected->{text}, "detector text / $size");
        is_deeply($actual->{events},   $expected->{events},   'detected sample timing');
        is_deeply($actual->{warnings}, $expected->{warnings}, 'rejection diagnostics');
        is($actual->{frequency}, $expected->{frequency}, 'tone selection');
    }
}
for my $bits (8, 16, 24) {
    my @bytes;
    for my $backend (qw(perl pdl)) {
        my $bytes = '';
        open my $out, '>:raw', \$bytes or die $!;
        Ham::RTTY::Audio->new(backend => $backend)->write(
            $out,
            [-1, -0.5, -0.5 / 2**($bits - 1), 0, 0.5 / 2**($bits - 1), 0.5, 1],
            bits        => $bits,
            sample_rate => 8000
        );
        close $out or die $!;
        push @bytes, $bytes;
    }
    is($bytes[1], $bytes[0], "PCM $bits is byte identical including rounding");
    open my $in, '<:raw', \$bytes[0] or die $!;
    my $expected = Ham::RTTY::Audio->new->read($in);
    seek($in, 0, 0) or die $!;
    is_deeply(Ham::RTTY::Audio->new(backend => 'pdl')->read($in), $expected, "PCM $bits decoding");
    close $in or die $!;
}
my $wav = '';
open my $out, '>:raw', \$wav or die $!;
my $cw = Ham::RTTY->new(backend => 'pdl', sample_rate => 8000);
$cw->generate_wav('SOS', $out);
close $out or die $!;
open my $in, '<:raw', \$wav or die $!;
is($cw->decode_wav($in, frequency => 700, wpm => 20)->text, 'SOS', 'PDL facade WAV integration');
close $in or die $!;

for my $bits (8, 16, 24) {
    my $raw =
          $bits == 8  ? pack('C*', 0, 255, 128, 64)
        : $bits == 16 ? pack('s<*', -32768, 32767, 0, -16384)
        :   join('', map { substr(pack('V', $_), 0, 3) } (8388608, 8388607, 0, 12582912));
    for my $policy (qw(left right mix)) {
        is_deeply(
            Ham::RTTY::_Internal::PDL::decode_pcm($raw, $bits, 2, $policy),
            Ham::RTTY::Audio::_decode_pcm($raw, $bits, 2, $policy),
            "stereo $bits / $policy"
        );
    }
}
for my $length (1, 2, 7) {
    my $sampled = {sample_rate => 8000, segments => [{state => 'on', samples => $length}]};
    my $perl = Ham::RTTY::Generator->new(sample_rate => 8000)->generate($sampled);
    my $fast = Ham::RTTY::Generator->new(sample_rate => 8000, backend => 'pdl')->generate($sampled);
    for my $i (0 .. $length - 1) {
        cmp_ok(abs($perl->[$i] - $fast->[$i]), '<', 1e-12, 'short mark ramps');
    }
}
my $detector = Ham::RTTY::Detector->new(backend => 'pdl', sample_rate => 8000, max_frames => 2);
eval { $detector->feed([(0) x 81]) };
is((ref($@) ? $@->code : "$@"), 'RTTY_E_RESOURCE', 'PDL frame limit');
is($detector->state,            'READY',         'PDL limit validation atomic');
eval { $detector->feed([0, 'NaN']) };
is((ref($@) ? $@->code : "$@"), 'RTTY_E_ARGUMENT', 'PDL validates input');
$detector->feed([(0) x 41]);
is($detector->result->complete, 0, 'PDL provisional result');
is($detector->finish->complete, 1, 'PDL flush partial frame');
is($detector->finish->complete, 1, 'PDL finish idempotent');
eval { $detector->feed([]) };
is((ref($@) ? $@->code : "$@"), 'RTTY_E_STATE', 'PDL feed after finish');
$detector->reset;
is($detector->state, 'READY', 'PDL reset');
is_deeply($detector->{pdl_kernels}, {}, 'reset releases cached kernels');
my $generator = Ham::RTTY::Generator->new(backend => 'pdl');
my $next      = $generator->stream($events, 11);
$next->();
$generator->reset;
eval { $next->() };
is((ref($@) ? $@->code : "$@"), 'RTTY_E_STATE', 'PDL invalidates reset stream');
open my $fixture, '<:raw', 'corpus/sos-650hz-20wpm.wav' or die $!;
is(Ham::RTTY->new(backend => 'pdl')->decode_wav($fixture)->text,
    'SOS', 'independent recorded fixture');
close $fixture or die $!;

my $empty =
    Ham::RTTY::Generator->new(backend => 'pdl')->stream({sample_rate => 16000, segments => []});
is($empty->(), undef, 'PDL empty generation');
my $silence = Ham::RTTY::Generator->new(backend => 'pdl')
    ->stream({sample_rate => 16000, segments => [{state => 'off', samples => 3}]});
is_deeply($silence->(), [0, 0, 0], 'PDL silence');
is($silence->(), undef, 'PDL iterator EOF');
my $no_ramps = Ham::RTTY::Generator->new(backend => 'pdl', attack_ms => 0, release_ms => 0);
is(
    scalar @{$no_ramps->generate($events)},
    scalar @{Ham::RTTY::Generator->new->generate($events)},
    'PDL zero ramps'
);
is_deeply([Ham::RTTY::_Internal::PDL::quantize([], 128)],          [], 'PDL empty quantization');
is_deeply(Ham::RTTY::_Internal::PDL::decode_pcm('', 16, 1, 'mix'), [], 'PDL empty PCM');
done_testing;
