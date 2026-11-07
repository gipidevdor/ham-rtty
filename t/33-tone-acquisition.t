use 5.020;
use strict;
use warnings FATAL => 'all';
use Test::More;
use Ham::RTTY::Detector;
use Ham::RTTY::_Internal::Backend;

my $rate     = 8000;
my $pi       = 4 * atan2(1, 1);
my @backends = ('perl');
push @backends, 'pdl' if Ham::RTTY::_Internal::Backend::resolve('auto') eq 'pdl';

# Independent ITA2 source: LTRS,C,Q,SPACE,T,E,S,T, without library synthesis.
sub signal {
    my ($mark, $reverse, $idle, $silence, $codes) = @_;
    $codes //= [31, 14, 23, 4, 16, 1, 5, 16];
    my @runs = ([1, $idle, $silence]);
    for my $code (@{$codes}) {
        push @runs, [0, 1 / 45.45];
        push @runs, [($code >> $_) & 1, 1 / 45.45] for 0 .. 4;
        push @runs, [1, 1.5 / 45.45];
    }
    push @runs, [1, 0.1] if @{$codes};
    my @audio;
    my ($phase, $time, $boundary) = (0, 0, 0);
    for my $run (@runs) {
        $time += $run->[1] * $rate;
        my $end = int($time + 0.5);
        for ($boundary .. $end - 1) {
            push @audio, $run->[2] ? 0 : 0.8 * sin($phase);
            my $high = (!$run->[0]) != $reverse;
            $phase += 2 * $pi * ($mark + ($high ? 170 : 0)) / $rate;
        }
        $boundary = $end;
    }
    return \@audio;
}

sub feed_chunks {
    my ($receiver, $values, $size) = @_;
    my $largest = 0;
    for (my $offset = 0; $offset < @{$values}; $offset += $size) {
        my $end = $offset + $size - 1;
        $end = $#{$values} if $end > $#{$values};
        $receiver->feed([@{$values}[$offset .. $end]]);
        my $pending = @{$receiver->{acquisition}};
        $largest = $pending if $pending > $largest;
    }
    cmp_ok($largest, '<=', $rate / 2, 'pending acquisition stays within half a second');
    return;
}

for my $backend (@backends) {
    for my $case ([1900, 0, 0.6, 0], [1900, 1, 0.6, 0], [1000, 0, 1.1, 1]) {
        my ($mark, $reverse, $idle, $silence) = @{$case};
        my $audio = signal(@{$case});
        my $label = "$backend mark $mark reverse $reverse idle $idle silence $silence";
        my $known = Ham::RTTY::Detector->new(
            sample_rate => $rate,
            backend     => $backend,
            mark        => $mark,
            reverse     => $reverse
        );
        $known->feed($audio);
        is($known->finish->text, 'CQ TEST', "$label independent reference");
        my $previous;
        for my $size (1, 137, 4096, scalar @{$audio}) {
            my $receiver = Ham::RTTY::Detector->new(
                sample_rate => $rate,
                backend     => $backend,
                reverse     => $reverse,
                search      => 1
            );
            feed_chunks($receiver, $audio, $size);
            my $result = $receiver->finish;
            is($result->text, 'CQ TEST', "$label block $size recovers the whole message");
            cmp_ok(abs($result->frequency - $mark), '<=', 10, 'acquires the correct tone pair');
            ok(!$result->has_warnings, 'clean acquisition has no reception warnings');
            is($result->diagnostics->{analyzed_samples}, scalar @{$audio}, 'counts all input');
            cmp_ok(
                $result->events->{segments}[0]{duration} // 0,
                '>=',
                ($idle - 0.03) * 1000000,
                'retains the idle prefix in event timing'
            );
            is_deeply($result->as_hash, $previous, 'acquisition is independent of input block size')
                if defined $previous;
            $previous = $result->as_hash;
        }
    }

    my $receiver = Ham::RTTY::Detector->new(
        sample_rate => $rate,
        backend     => $backend,
        search      => 1
    );
    my $initial = $receiver->result->as_hash;
    for my $silence (0, 1) {
        $receiver->reset;
        feed_chunks($receiver, signal(1900, 0, 1.1, $silence, []), 137);
        my $before = $receiver->result->as_hash;
        eval { $receiver->feed([2]) };
        is(ref($@) ? $@->code : '', 'RTTY_E_ARGUMENT', 'invalid pending feed is rejected');
        is_deeply($receiver->result->as_hash, $before, 'rejection preserves pending acquisition');
        my $result = $receiver->finish;
        is($result->text,                '', 'a single carrier or silence cannot produce text');
        is($result->warnings->[0]{code}, 'RTTY_W_NO_SIGNAL', 'missing tone pair is reported');
        is($result->frequency,           2125, 'unresolved search does not invent a frequency');
        is_deeply($receiver->finish->as_hash, $result->as_hash, 'finish remains idempotent');
    }
    is_deeply($receiver->reset->result->as_hash, $initial, 'reset clears deferred acquisition');
    $receiver->feed(signal(1900, 0, 0.1, 0, [1]));
    is($receiver->finish->text, 'E', 'finish acquires a message shorter than half a second');

    # The initial FIGS start falls in the last, unanalyzed part of the first
    # acquisition window. Losing it would decode the following digits as QWE.
    my $boundary = signal(1900, 0, 0.4995, 0, [27, 23, 19, 1]);
    my $previous;
    for my $size (137, scalar @{$boundary}) {
        my $receiver = Ham::RTTY::Detector->new(
            sample_rate => $rate,
            backend     => $backend,
            search      => 1
        );
        feed_chunks($receiver, $boundary, $size);
        my $result = $receiver->finish;
        is($result->text, '123', 'overlapping acquisition preserves the first FIGS frame');
        ok(!$result->has_warnings, 'a frame across the retry boundary has valid framing');
        is_deeply($result->as_hash, $previous, 'retry overlap is block independent')
            if defined $previous;
        $previous = $result->as_hash;
    }

    my $limited = Ham::RTTY::Detector->new(
        sample_rate => $rate,
        backend     => $backend,
        search      => 1,
        max_frames  => 2000
    );
    $limited->feed(signal(1900, 0, 0.6, 0, []));
    my $before = $limited->result->as_hash;
    eval { $limited->feed([(0) x 30000]) };
    is(ref($@) ? $@->code : '', 'RTTY_E_RESOURCE', 'pending search still enforces frame budgets');
    is_deeply($limited->result->as_hash, $before, 'resource rejection preserves pending search');
    $limited->feed(signal(1900, 0, 0, 0));
    is($limited->finish->text, 'CQ TEST', 'search recovers after a rejected oversized feed');
}

done_testing;
