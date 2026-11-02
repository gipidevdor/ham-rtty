use 5.020;
use strict;
use warnings FATAL => 'all';
use Test::More;
use Ham::RTTY;
use Ham::RTTY::Decoder;
use Ham::RTTY::Encoder;
use Ham::RTTY::Events qw(validate_events to_samples to_timed);
use Ham::RTTY::Generator;
use Ham::RTTY::MIDI;

my $rtty = Ham::RTTY->new;
for my $rate (44100, 384000) {
    my $events = $rtty->sampled_events(
        'CQ 73',
        sample_rate   => $rate,
        baud          => 300,
        leading_idle  => 0,
        trailing_idle => 0
    );
    my $whole = Ham::RTTY::Decoder->new(baud => 300);
    $whole->feed($events);
    my $expected = $whole->finish->as_hash;
    is($expected->{text}, 'CQ 73', "$rate Hz reference message");
    for my $size (1, 37, 4096) {
        my $split = Ham::RTTY::Decoder->new(baud => 300);
        for my $run (@{$events->{segments}}) {
            my $left = $run->{samples};
            while ($left) {
                my $count = $left < $size ? $left : $size;
                $split->feed(
                    {
                        sample_rate => $rate,
                        segments    => [{state => $run->{state}, samples => $count}]
                    }
                );
                $left -= $count;
            }
        }
        is_deeply($split->finish->as_hash,
            $expected, "$rate Hz chunks of $size preserve text, timing and warnings");
    }
    my $reset = Ham::RTTY::Decoder->new;
    $reset->feed({sample_rate => $rate, segments => [{state => 'mark', samples => 1}]});
    $reset->reset->feed($events);
    my $fresh = Ham::RTTY::Decoder->new;
    $fresh->feed($events);
    is_deeply($reset->finish->as_hash, $fresh->finish->as_hash, 'reset clears conversion carry');
}

my $limited = Ham::RTTY::Decoder->new(max_segments => 1);
my $mark    = {unit => 'us', segments => [{state => 'mark', duration => 100}]};
$limited->feed($mark)->feed($mark);
is_deeply(
    $limited->result->events->{segments},
    [{state => 'mark', duration => 200}],
    'equal states share one retained segment at the ceiling'
);
my $before = $limited->result->as_hash;
eval { $limited->feed({sample_rate => 384000, segments => [{state => 'space', samples => 1}]}) };
is(ref($@) ? $@->code : '', 'RTTY_E_RESOURCE', 'new run still exceeds the ceiling');
is_deeply($limited->result->as_hash, $before, 'rejection preserves state');
$limited->feed($mark);
is($limited->result->events->{segments}[0]{duration},
    300, 'rejected conversion does not alter the clock');

my $large = {
    unit     => 'us',
    segments => [map { +{state => $_ % 2 ? 'mark' : 'space', duration => 1000} } 0 .. 100000]
};
eval { Ham::RTTY::Decoder->new->feed($large) };
is(ref($@) ? $@->code : '', 'RTTY_E_RESOURCE', 'default history ceiling remains enforced');
my $expanded = Ham::RTTY::Decoder->new(max_segments => 200000);
$expanded->feed($large);
is(scalar @{$expanded->result->events->{segments}}, 100001, 'expanded history can be snapshotted');
is($expanded->finish->complete,                     1,      'expanded history can be finalized');
my $sampled = to_samples($large, 8000, 200000);
is(scalar @{$sampled->{segments}}, 100001, 'explicit conversion ceiling propagates');
is_deeply(to_timed($sampled, 200000), $large, 'large sampled sequence converts back');
my $next = Ham::RTTY::Generator->new(sample_rate => 8000)->stream($large);
is(scalar @{$next->()}, 4096, 'generator accepts expanded event sequences');
my $midi = Ham::RTTY::MIDI->new(bpm => 240, ppqn => 1000)->encode($large);
is(substr($midi, 0, 4), 'MThd', 'MIDI accepts expanded event sequences');

for my $idle (0, 0.0000001, 0.00000049, 0.0000005, 0.000001) {
    my $events = Ham::RTTY::Encoder->new(leading_idle => $idle)->events('E');
    is(validate_events($events), 'duration', "valid events for idle $idle");
    ok(!grep({ $_->{duration} <= 0 } @{$events->{segments}}), 'no zero-length run');
    if ($idle < 0.0000005) {
        ok(@{$rtty->samples('E', leading_idle => $idle)}, 'audio accepts omitted zero idle');
    }
    else {
        eval { $rtty->samples('E', leading_idle => $idle) };
        is(ref($@) ? $@->code : '',
            'RTTY_E_TIMING',
            'positive microsecond idle below sample resolution has an explicit timing error');
    }
}
my $audio_result = $rtty->decode_samples($rtty->samples('CQ'));
is($audio_result->events->{unit}, 'us', 'audio result documents timed microseconds');
my $event_result = $rtty->decode_events($rtty->sampled_events('CQ'));
is($event_result->events->{unit}, 'us', 'sampled input normalizes to timed result');

my $mixed = Ham::RTTY::Decoder->new;
$mixed->feed({sample_rate => 384000, segments => [{state => 'mark', samples  => 1}]});
$mixed->feed({unit        => 'us',   segments => [{state => 'mark', duration => 1}]});
$mixed->feed({sample_rate => 384000, segments => [{state => 'mark', samples  => 1}]});
is($mixed->result->events->{segments}[0]{duration},
    6, 'changing input units preserves fractional time');
my $same = Ham::RTTY::Decoder->new;
$same->feed({sample_rate => 384000, segments => [{state => 'mark', samples => 1}]});
$same->feed({unit        => 'us',   segments => []});
$same->feed({sample_rate => 384000, segments => [{state => 'mark', samples => 1}]});
is($same->result->events->{segments}[0]{duration}, 5,
    'empty blocks do not discard fractional time');

# A failed event conversion must not publish an intermediate frame result.
for my $lenient (0, 1) {
    my $encoder = Ham::RTTY::Encoder->new(max_segments => 3, lenient => $lenient);
    $encoder->encode('E');
    my $saved = $encoder->result->as_hash;
    my $input = $lenient ? "\x{2603}" : 'A';
    eval { $encoder->events($input) };
    is(ref($@) ? $@->code : '', 'RTTY_E_RESOURCE', 'event run overflow is rejected');
    is_deeply($encoder->result->as_hash, $saved, 'failed events preserve text and warnings');
    $encoder->frames('T');
    is($encoder->result->text, 'T', 'encoder remains reusable after rejection');
}
my $fresh_encoder = Ham::RTTY::Encoder->new(max_segments => 3);
eval { $fresh_encoder->events('A') };
is($fresh_encoder->result->complete, 0, 'first failed encoding leaves a provisional result');

# EOF framing diagnostics must agree with warnings and remain idempotent.
my $truncated = Ham::RTTY::Decoder->new(baud => 50);
$truncated->feed(
    {
        unit     => 'bits',
        baud     => 50,
        segments => [{state => 'space', duration => 1}]
    }
);
is($truncated->result->diagnostics->{framing_error_count}, 0, 'pending frame is not yet an error');
my $ended = $truncated->finish;
is($ended->diagnostics->{framing_error_count}, 1, 'EOF counts the incomplete frame');
is(scalar @{$ended->warnings},                 1, 'EOF emits one warning');
is_deeply($truncated->finish->as_hash, $ended->as_hash, 'repeated finish does not recount EOF');
$truncated->reset;
is($truncated->result->diagnostics->{framing_error_count}, 0, 'reset clears EOF errors');

{

    package StringifiedOption;
    use overload q{""} => sub { return $_[0]{value} }, fallback => 1;
}
my $guarded = Ham::RTTY::Decoder->new;
$guarded->feed({unit => 'us', segments => [{state => 'mark', duration => 1000}]});
my $untouched = $guarded->result->as_hash;
for my $state ([], bless({value => 'space'}, 'StringifiedOption')) {
    eval { $guarded->feed({unit => 'us', segments => [{state => $state, duration => 1000}]}) };
    is(ref($@) ? $@->code : '', 'RTTY_E_ARGUMENT', 'reference event states are rejected');
    is_deeply($guarded->result->as_hash, $untouched, 'invalid state cannot poison decoder history');
}
eval { Ham::RTTY::Audio->new(stereo => bless({value => 'mix'}, 'StringifiedOption')) };
is(ref($@) ? $@->code : '', 'RTTY_E_ARGUMENT', 'stereo policy requires a scalar value');

# Exercise every assigned character across source timing resolutions.
for my $variant (qw(ita2 us)) {
    my $tables = Ham::RTTY::Baudot->new(variant => $variant)->tables;
    my $text   = join '', grep { defined } @{$tables->{letters}}, @{$tables->{figures}};
    for my $baud (20, 45.45, 50, 75, 100, 300) {
        for my $rate (1000, 8000, 44100, 384000) {
            for my $stop (1, 1.5, 2) {
                my $events = $rtty->sampled_events(
                    $text,
                    baud          => $baud,
                    sample_rate   => $rate,
                    stop_bits     => $stop,
                    variant       => $variant,
                    leading_idle  => 0,
                    trailing_idle => 0
                );
                my $decoder = $rtty->decoder(baud => $baud, variant => $variant);
                $decoder->feed({sample_rate => $rate, segments => [$_]})
                    for @{$events->{segments}};
                my $result = $decoder->finish;
                is($result->text, $text,
                    "$variant / $baud baud / $rate Hz / $stop stop: repertoire");
                ok(!$result->has_warnings, 'clean complete frames have no warnings');
            }
        }
    }
}

done_testing;
