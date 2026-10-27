use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use File::Spec;
use Ham::RTTY;
use lib 't/lib';
use Reference qw(reference_sos noise);

my @backends = ('perl');
push @backends, 'pdl' if eval { require Ham::RTTY::_Internal::PDL; 1 };
for my $backend (@backends) {
    for my $amplitude (0.01, 0.02) {
        my $samples = reference_sos(amplitude => $amplitude);
        $samples->[$_] = 0.3 * sin(2 * 3.14159265358979 * 650 * $_ / 8000) for 400 .. 439;
        my $reference;
        for my $block (137, 4096) {
            my $detector = Ham::RTTY::Detector->new(
                sample_rate => 8000,
                frequency   => 650,
                wpm         => 20,
                backend     => $backend
            );
            for (my $i = 0; $i < @{$samples}; $i += $block) {
                my $end = $i + $block - 1;
                $end = $#{$samples} if $end > $#{$samples};
                $detector->feed([@{$samples}[$i .. $end]]);
            }
            my $result = $detector->finish;
            is($result->text, 'SOS', "$backend weak CW after a stronger impulse, $block samples");
            $reference //= $result->events;
            is_deeply($result->events, $reference, 'impulse rejection is independent of blocks');
        }
    }
}
for my $backend (@backends) {
    for my $amplitude (0.10, 0.30) {
        for my $kind ('tone', 'noise') {
            my @samples = ((0) x 4000, @{reference_sos(amplitude => $amplitude)});
            my $burst =
                $kind eq 'noise'
                ? noise(40, 1)
                : [map { sin(2 * 3.14159265358979 * 650 * $_ / 8000) } 0 .. 39];

            # Unaligned burst straddles two frames.
            $samples[407 + $_] = $burst->[$_] for 0 .. 39;
            for my $hints (0, 1) {
                my $d = Ham::RTTY::Detector->new(
                    sample_rate => 8000,
                    backend     => $backend,
                    $hints ? (frequency => 650, wpm => 20) : ()
                );
                $d->feed(\@samples);
                is($d->finish->text, 'SOS',
                    "$backend $kind impulse with amplitude $amplitude, hints $hints");
            }
        }
    }
}

# A strong burst inside a weak dash must neither split nor shorten it.
for my $backend (@backends) {
    my $samples = reference_sos(amplitude => 0.05);
    $samples->[8000 + $_] += 0.4 * sin(2 * 3.14159265358979 * 650 * (8000 + $_) / 8000)
        for 0 .. 39;
    my $result = Ham::RTTY->new->decode_samples(
        $samples,
        sample_rate => 8000,
        frequency   => 650,
        wpm         => 20,
        backend     => $backend
    );
    is($result->text, 'SOS', "$backend burst inside a mark leaves the mark intact");
}

# Exercise every tenth-WPM value including equal fractional configured speeds.
my @failed;
for my $tenth (50 .. 600) {
    my $speed = $tenth / 10;
    my $cw    = Ham::RTTY->new(wpm => $speed, effective_wpm => $speed);
    my $r = eval { $cw->decode_events($cw->events('SOS'), wpm => $speed, effective_wpm => $speed) };
    push @failed, $speed if !$r || $r->text ne 'SOS' || @{$r->warnings};
}
is_deeply(\@failed, [], 'all 551 equal fractional speeds decode without warnings');
for my $backend (@backends) {
    my $d = Ham::RTTY::Detector->new(sample_rate => 8000, backend => $backend, effective_wpm => 60);
    $d->feed(reference_sos());
    my $provisional = $d->result;
    my $final       = $d->finish;
    ok($provisional,     "$backend estimated speed mismatch permits result");
    ok($final->complete, "$backend estimated speed mismatch permits finish");
    is($d->state, 'FINISHED', "$backend completes lifecycle");
    ok(grep($_->{code} eq 'RTTY_W_SPACING_AMBIGUOUS', @{$final->warnings}),
        'mismatch has structured warning');
    is($final->text, 'SOS', 'mismatch keeps usable text');
}
eval { Ham::RTTY::Detector->new(effective_wpm => 61) };
is(ref($@) ? $@->code : "$@", 'RTTY_E_ARGUMENT', 'effective reception speed capped at 60');
my $cw     = Ham::RTTY->new;
my $events = $cw->events('SOS');
unshift @{$events->{segments}}, {state => 'off', duration => 30000000};
push @{$events->{segments}},    {state => 'off', duration => 30000000};
my $result = $cw->decode_events($events);
is($result->text, 'SOS', 'recording margins preserve text');
ok(!grep($_->{code} eq 'RTTY_W_SPACING_AMBIGUOUS', @{$result->warnings}),
    'recording margins do not suggest Farnsworth');
$events = $cw->events('CQ TEST');
my ($gap) = grep { $_->{state} eq 'off' && $_->{duration} > 120000 } @{$events->{segments}};
$gap->{duration} = 3000000;
$result = $cw->decode_events($events);
ok(!grep($_->{code} eq 'RTTY_W_SPACING_AMBIGUOUS', @{$result->warnings}),
    'isolated operator pause does not suggest Farnsworth');
my $root = tempdir(CLEANUP => 1);

for my $format (qw(wav midi)) {
    my $method = "write_$format";
    my $file   = File::Spec->catfile($root, "message.$format");
    $cw->$method('SOS', $file);
    my $before;
    { open my $in, '<:raw', $file or die $!; local $/; $before = <$in>; close $in or die $!; }
    eval { $cw->$method('!', $file, overwrite => 1) };
    is(ref($@) ? $@->code : "$@", 'RTTY_E_SYMBOL', "$format overwrite reports generation failure");
    my $after;
    { open my $in, '<:raw', $file or die $!; local $/; $after = <$in>; close $in or die $!; }
    is($after, $before, "$format failure preserves existing bytes");
    ok($cw->$method('CQ TEST', $file, overwrite => 1), "$format explicit replacement succeeds");
    eval { $cw->$method('SOS', $file, overwrite => 2) };
    is(ref($@) ? $@->code : "$@", 'RTTY_E_ARGUMENT', "$format overwrite validates boolean");
}
is($cw->read_wav(File::Spec->catfile($root, 'message.wav'))->text,
    'CQ TEST', 'replacement WAV contains new message');
my @temporary = glob(File::Spec->catfile($root, '.ham-rtty-*'));
is_deeply(\@temporary, [], 'replacement cleans temporary files');
done_testing;
