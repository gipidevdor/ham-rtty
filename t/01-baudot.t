use 5.020;
use strict;
use warnings FATAL => 'all';
use Test::More;
use Ham::RTTY::Baudot;
use Ham::RTTY::Encoder;
use Ham::RTTY::Decoder;
use Ham::RTTY::Events qw(validate_events to_samples to_timed);

for my $variant (qw(ita2 us)) {
    my $tables = Ham::RTTY::Baudot->new(variant => $variant)->tables;
    my $e      = Ham::RTTY::Encoder->new(variant => $variant);
    my $d      = Ham::RTTY::Decoder->new(variant => $variant);
    for my $mode (qw(letters figures)) {
        for my $code (0 .. 31) {
            next unless defined $tables->{$mode}[$code];
            my $c = $tables->{$mode}[$code];
            is($d->decode($e->encode($c)), $c, "$variant $mode code $code notation");
            is($d->reset->decode_bits($e->bits($c))->text, $c, "$variant $mode code $code bits");
            $d->reset->feed($e->events($c));
            is($d->finish->text, $c, "$variant $mode code $code events");
        }
    }
}
my $e = Ham::RTTY::Encoder->new;
is($e->encode('A'),                                       '[LTRS] 00011',  'known S.1 A vector');
is($e->frames('A')->[1]{data_bits},                       '11000',         'LSB first');
is(Ham::RTTY::Decoder->new->decode('[FIGS] 00100 00001'), ' E',            'USOS receiver');
is(Ham::RTTY::Decoder->new(usos => 0)->decode('[FIGS] 00100 00001'), ' 3', 'USOS disabled');
is($e->encode('1 2'), '[FIGS] 10111 00100 [FIGS] 10011', 'FIGS resent after space');
is(Ham::RTTY::Encoder->new(usos => 0)->encode('1 2'), '[FIGS] 10111 00100 10011', 'FIGS retained');
is(Ham::RTTY::Decoder->new->decode('[FIGS] [FIGS] [LTRS] 00011'), 'A', 'repeated shifts');
my $lenient = Ham::RTTY::Encoder->new(lenient => 1);
is(Ham::RTTY::Decoder->new->decode($lenient->encode('a@')), 'A?',            'lenient replacement');
is($lenient->result->warnings->[0]{code},                   'RTTY_W_SYMBOL', 'encoding warning');

for my $args (
    [baud      => 19],
    [baud      => 301],
    [stop_bits => 1.2],
    [variant   => 'bad'],
    [usos      => 2],
    [lenient   => 2],
    [baud      => 50, baud => 75], ['odd']
    )
{
    ok(!eval { Ham::RTTY::Encoder->new(@{$args}); 1 }, 'reject invalid encoder arguments');
}
ok(!eval { $e->encode('@');                        1 }, 'unsupported ITU character');
ok(!eval { Ham::RTTY::Decoder->new->decode('abc'); 1 }, 'reject notation');
my $events = $e->events('TEST 123');
is(validate_events($events),                             'duration', 'valid events');
is(validate_events(to_samples($events, 8000)),           'samples',  'sample conversion');
is(validate_events(to_timed(to_samples($events, 8000))), 'duration', 'timed conversion');
my $d = Ham::RTTY::Decoder->new;
for my $s (@{$events->{segments}}) { $d->feed({unit => 'us', segments => [$s]}) }
is($d->finish->text, 'TEST 123', 'single run feeds');
my $snapshot = $d->result;
$d->reset;
is($snapshot->text, 'TEST 123', 'independent snapshot');
my $copy = $snapshot->events;
$copy->{segments}[0]{duration} = 1;
isnt($snapshot->events->{segments}[0]{duration}, 1, 'deep copied events');
done_testing;
