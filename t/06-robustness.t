use 5.020;
use strict;
use warnings FATAL => 'all';
use Test::More;
use Ham::RTTY;
use Ham::RTTY::Detector;
my $rate = 8000;
my $pi   = 4 * atan2(1, 1);

# Independent source: S.1 numeric codes LTRS,C,Q,SPACE,FIGS,1,2,3,LTRS.
# No Encoder, Events or Generator calls construct these samples.
sub independent_signal {
    my ($space_gain, $interferer) = @_;
    my @runs = ([1, 0.15]);
    for my $code (31, 14, 23, 4, 27, 23, 19, 1, 31) {
        push @runs, [0, 1 / 45.45];
        push @runs, [($code >> $_) & 1, 1 / 45.45] for 0 .. 4;
        push @runs, [1, 1.5 / 45.45];
    }
    push @runs, [1, 0.15];
    my @audio;
    my ($phase, $time, $boundary) = (0, 0, 0);

    # Keep counters separate from the variable-length audio array.
    @audio = ();
    ($phase, $time, $boundary) = (0, 0, 0);
    for my $run (@runs) {
        $time += $run->[1] * $rate;
        my $end = int($time + 0.5);
        for ($boundary .. $end - 1) {
            my $gain = $run->[0] ? 0.2 : $space_gain;
            push @audio,
                ($gain * sin($phase) + $interferer * sin(2 * $pi * 1100 * @audio / $rate)) / 1.2;
            $phase += 2 * $pi * ($run->[0] ? 2125 : 2295) / $rate;
        }
        $boundary = $end;
    }
    return \@audio;
}
for my $gain (0.1, 0.2, 0.5) {
    for my $carrier (0, 0.6) {
        my $result = Ham::RTTY->new(sample_rate => $rate)
            ->decode_samples(independent_signal($gain, $carrier));
        is($result->text, 'CQ 123', "independent source space=$gain carrier=$carrier");
    }
}
my $rtty  = Ham::RTTY->new(sample_rate => $rate);
my $audio = $rtty->samples('PREFIX CQ TEST CQ TEST');
my @cut   = @{$audio}[2300 .. $#{$audio}];
like(
    $rtty->decode_samples(\@cut)->text,
    qr/CQ TEST CQ TEST\z/,
    'mid-stream reacquisition recovers suffix'
);
my $detector = $rtty->detector(max_frames => 5);
my $before   = $detector->result->as_hash;
ok(!eval { $detector->feed([(0) x 8000]); 1 }, 'overflow rejected');
is_deeply($detector->result->as_hash, $before, 'overflow preserves state');
ok(!eval { $detector->feed([2]); 1 }, 'invalid sample rejected');
is($detector->state, 'READY', 'invalid sample preserves lifecycle');
my $decoder = $rtty->decoder;
$decoder->feed(
    {
        unit     => 'bits',
        baud     => 45.45,
        segments => [{state => 'space', duration => 7}, {state => 'mark', duration => 2}]
    }
);
is($decoder->finish->warnings->[0]{code}, 'RTTY_W_FRAMING', 'bad stop warns');
my $valid = $rtty->events('A');
my $dec   = $rtty->decoder(max_segments => 1);
ok(!eval { $dec->feed($valid); 1 }, 'event limit');
is($dec->state, 'READY', 'event limit atomic');
done_testing;
