use strict;
use warnings;
use Test::More;
use JSON::PP;
use Ham::RTTY;
use Ham::RTTY::_Internal::CLI;
use lib 't/lib';
use Reference qw(reference_sos noise);

my $detector = Ham::RTTY::Detector->new(sample_rate => 8000, frequency => 650, wpm => 20);

# A long OFF preamble moves the tracker noise from the global seed (1) to
# local power 2. The existing global gate is 12, so these runs clear
# hysteresis but straddle the new local 10 dB power-ratio requirement.
for my $case ([19.98, 0], [20, 1], [20.02, 1]) {
    my @power    = ((2) x 1000, ($case->[0]) x 6, (2) x 40);
    my @frames   = map { +{samples => 40} } @power;
    my $segments = $detector->_segment(\@frames, \@power, 1, 100);
    is(scalar(grep { $_->{state} eq 'on' } @{$segments}),
        $case->[1], "mean power $case->[0] relative to run-start noise 2");
    my $total = 0;
    $total += $_->{samples} for @{$segments};
    is($total, scalar(@power) * 40, 'mark rejection preserves total duration');
}
{
    my @power  = ((2) x 1000, (13) x 6, 2, (50) x 24, (2) x 40);
    my @frames = map { +{samples => 40} } @power;
    is_deeply(
        $detector->_segment(\@frames, \@power, 1, 100),
        [
            {state => 'off', samples => 40280},
            {state => 'on',  samples => 960},
            {state => 'off', samples => 1600}
        ],
        'weak 30 ms run is rejected before a 5 ms gap can glue it to a strong mark'
    );
}
{
    my @power  = ((2) x 30, (20) x 10, (11.9) x 200);
    my @frames = map { +{samples => 40} } @power;
    is(scalar(grep { $_->{state} eq 'on' } @{$detector->_segment(\@frames, \@power, 1, 100)}),
        1, 'run-start tracker noise is used, not the higher noise after the run');
}
{
    my @power    = ((2) x 1000, 18, 24);
    my @frames   = ((map { +{samples => 40} } 1 .. 1001), {samples => 10});
    my $segments = $detector->_segment(\@frames, \@power, 1, 100);
    is(scalar(grep { $_->{state} eq 'on' } @{$segments}),
        0, 'partial-hop weighting gives mean 19.2, not unweighted 21');
}
for my $value (-0.1, 40.1, 'NaN', []) {
    eval { Ham::RTTY::Detector->new(mark_snr_db => $value) };
    is(ref($@) ? $@->code : "$@", 'RTTY_E_ARGUMENT', 'mark SNR range and type are validated');
}
ok(Ham::RTTY::Detector->new(mark_snr_db => 40), 'upper limit is accepted');

my $amplitude = 0.5;
my $signal    = reference_sos(amplitude => $amplitude);
my @base      = ((0) x 8000, @{$signal}, (0) x 8000);

# Uniform white-noise RMS is amplitude/sqrt(3), sine RMS amplitude/sqrt(2).
my $background  = noise(scalar(@base), $amplitude * sqrt(3 / 2) / 10);
my $noise_power = 0;
$noise_power += $_ * $_ for @{$background};
$noise_power /= @{$background};
cmp_ok(abs(10 * log(($amplitude**2 / 2) / $noise_power) / log(10) - 20),
    '<', 0.2, 'independent SOS fixture has nominal 20 dB broadband SNR during marks');
$base[$_] += $background->[$_] for 0 .. $#base;
my @backends = ('perl');
push @backends, 'pdl' if eval { require Ham::RTTY::_Internal::PDL; 1 };

for my $level (-25, -3) {
    my @samples = @base;
    my $gain    = $amplitude * 10**($level / 20);
    for my $time (0.15, 0.35, 0.55, 0.75, 3.2) {
        my $start = int($time * 8000);
        $samples[$_] += $gain * sin(2 * atan2(0, -1) * 650 * $_ / 8000) for $start .. $start + 239;
    }
    my $reference;
    for my $backend (@backends) {
        for my $chunk (137, 4096) {
            my $d = Ham::RTTY::Detector->new(
                sample_rate => 8000,
                frequency   => 650,
                wpm         => 20,
                backend     => $backend
            );
            for (my $i = 0; $i < @samples; $i += $chunk) {
                my $end = $i + $chunk - 1 < $#samples ? $i + $chunk - 1 : $#samples;
                $d->feed([@samples[$i .. $end]]);
            }
            my $r = $d->finish;
            is(
                $r->text,
                $level == -25 ? 'SOS' : 'EEEE SOS E',
                "$backend / $chunk: five 30 ms bursts at $level dB preserve expected behavior"
            );
            my $summary = {
                text      => $r->text,
                events    => $r->events,
                warnings  => $r->warnings,
                frequency => $r->frequency
            };
            $reference //= $summary;
            is_deeply($summary, $reference, 'mark gate preserves backend/chunk equivalence');
            is($r->diagnostics->{mark_snr_db}, 10, 'default mark gate is reported');
        }
    }
    if ($level == -3) {
        my $control = Ham::RTTY->new->decode_samples(
            \@samples,
            sample_rate => 8000,
            frequency   => 650,
            wpm         => 20,
            mark_snr_db => 0
        );
        is($control->text, 'EEEE SOS E', 'strong-burst behavior agrees with disabled mark gate');
        is_deeply($control->events, $reference->{events},
            'strong-burst timing is unchanged by mark admission');
    }
}
my $cw = Ham::RTTY->new(sample_rate => 8000, frequency => 650, wpm => 20);
my $result =
    $cw->decode_wav_bytes($cw->wav_bytes('SOS'), frequency => 650, wpm => 20, mark_snr_db => 0);
is($result->text,                       'SOS', 'WAV facade accepts mark_snr_db');
is($result->diagnostics->{mark_snr_db}, 0,     'WAV facade forwards the value');
for my $value (10, -1) {
    open my $in,  '<', \my $empty  or die $!;
    open my $out, '>', \my $output or die $!;
    open my $err, '>', \my $errors or die $!;
    my $status = Ham::RTTY::_Internal::CLI::run(
        [
            'receive', '--mark-snr-db', "$value", '--frequency', '650', '--wpm', '20', '--json',
            'corpus/sos-650hz-20wpm.wav'
        ],
        $in, $out, $err
    );
    is($status, $value == 10 ? 0 : 2, 'CLI accepts mark SNR and rejects invalid range');
    is(JSON::PP->new->decode($output)->{diagnostics}{mark_snr_db}, 10, 'CLI forwards mark SNR')
        if $value == 10;
}
done_testing;
