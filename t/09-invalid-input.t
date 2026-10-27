use 5.020;
use strict;
use warnings FATAL => 'all';
use Test::More;
use Ham::RTTY;
use Ham::RTTY::Events              qw(validate_events to_samples to_timed);
use Ham::RTTY::_Internal::Validate qw(samples);
use Ham::RTTY::_Internal::Data     qw(plain_data);

sub error_is {
    my ($code, $action, $label) = @_;
    my $ok    = eval { $action->(); 1 };
    my $error = $@;
    ok(!$ok, $label);
    isa_ok($error, 'Ham::RTTY::Error');
    is(ref($error) ? $error->code : '', $code, 'stable error code');
}
for my $class (
    qw(Ham::RTTY Ham::RTTY::Encoder Ham::RTTY::Decoder Ham::RTTY::Generator Ham::RTTY::Detector Ham::RTTY::Audio Ham::RTTY::MIDI Ham::RTTY::Result)
    )
{
    error_is('RTTY_E_ARGUMENT', sub { $class->new(unknown_option => 1) }, "$class unknown option");
    error_is('RTTY_E_ARGUMENT', sub { $class->new('odd') },               "$class odd arguments");
    error_is('RTTY_E_ARGUMENT', sub { $class->new(undef, 1) }, "$class undefined option");
}
for my $value (undef, [], {}) {
    error_is('RTTY_E_ARGUMENT', sub { Ham::RTTY->new->encode($value) }, 'text type');
    error_is('RTTY_E_ARGUMENT', sub { Ham::RTTY->new->decode($value) }, 'notation type');
    error_is('RTTY_E_ARGUMENT', sub { Ham::RTTY::Decoder->new->decode_bits($value) }, 'bits type');
    error_is('RTTY_E_ARGUMENT', sub { Ham::RTTY->new->decode_wav_bytes($value) }, 'WAV byte type');
}
for my $value ('NaN', 'Inf', [], 'bad', 19, 301) {
    error_is('RTTY_E_ARGUMENT', sub { Ham::RTTY::Encoder->new(baud => $value) }, 'finite baud');
}
for my $events (
    undef,
    [],
    {},
    {unit        => 'us',   segments    => {}},
    {unit        => 'us',   sample_rate => 8000, segments => []},
    {unit        => undef,  segments    => []},
    {unit        => [],     segments    => []},
    {unit        => 'bad',  segments    => []},
    {sample_rate => 1,      segments    => []},
    {unit        => 'bits', segments    => []},
    {unit        => 'us',   segments    => [undef]},
    {unit        => 'us',   segments    => [{state => 'invalid', duration => 1}]},
    {unit        => 'us',   segments    => [{state => 'mark',    duration => 1.5}]},
    {unit        => 's',    segments    => [{state => 'space',   duration => 0}]}
    )
{
    error_is('RTTY_E_ARGUMENT', sub { validate_events($events) }, 'invalid event shape/header');
}
error_is(
    'RTTY_E_TIMING',
    sub {
        validate_events(
            {
                unit     => 'us',
                segments => [{state => 'mark', duration => 1}, {state => 'mark', duration => 2}]
            }
        );
    },
    'alternation'
);
error_is(
    'RTTY_E_RESOURCE',
    sub {
        validate_events(
            {
                unit     => 'us',
                segments =>
                    [{state => 'mark', duration => 2**52}, {state => 'space', duration => 1}]
            }
        );
    },
    'duration overflow'
);
error_is(
    'RTTY_E_RESOURCE',
    sub { validate_events(Ham::RTTY->new->events('A'), 1) },
    'segment ceiling'
);
error_is(
    'RTTY_E_ARGUMENT',
    sub { to_samples({sample_rate => 8000, segments => []}, 8000) },
    'conversion direction'
);
error_is(
    'RTTY_E_TIMING',
    sub { to_samples({unit => 'us', segments => [{state => 'mark', duration => 1}]}, 8000) },
    'sample resolution'
);
error_is(
    'RTTY_E_RESOURCE',
    sub { to_timed({sample_rate => 1000, segments => [{state => 'mark', samples => 2**52}]}) },
    'converted overflow'
);
is(
    to_samples({unit => 's', segments => [{state => 'mark', duration => 0.01}]}, 8000)
        ->{segments}[0]{samples},
    80,
    'seconds conversion'
);
is(
    to_samples(
        {unit => 'bits', baud => 50, segments => [{state => 'mark', duration => 1.5}]}, 8000
    )->{segments}[0]{samples},
    240,
    'fractional bits conversion'
);
error_is('RTTY_E_ARGUMENT', sub { samples({},        2) }, 'sample container');
error_is('RTTY_E_RESOURCE', sub { samples([0, 0, 0], 2) }, 'sample block limit');

for my $bad (undef, {}, 'Inf', -1.01, 1.01) {
    error_is('RTTY_E_ARGUMENT', sub { Ham::RTTY::Detector->new->feed([$bad]) }, 'sample values');
}
error_is('RTTY_E_ARGUMENT', sub { Ham::RTTY::Generator->new(sample_rate => 16000.5) },
    'integer rate');
error_is(
    'RTTY_E_ARGUMENT',
    sub { Ham::RTTY::Generator->new->generate({sample_rate => 8000, segments => []}) },
    'rate mismatch'
);
my $empty_gen = Ham::RTTY::Generator->new;
is_deeply($empty_gen->generate({unit => 'us', segments => []}), [], 'empty generation');
is($empty_gen->result->{samples}, 0, 'generation statistics');
error_is('RTTY_E_RESOURCE', sub { Ham::RTTY::Encoder->new(max_segments => 1)->encode('A') },
    'frame limit');
error_is('RTTY_E_RESOURCE', sub { Ham::RTTY::Encoder->new(max_segments => 3)->events('T') },
    'run limit');
error_is(
    'RTTY_E_SYMBOL',
    sub {
        Ham::RTTY::Baudot->new->character(27);
        my $b = Ham::RTTY::Baudot->new;
        $b->character(27);
        $b->character(13);
    },
    'unassigned national combination'
);
error_is(
    'RTTY_E_SYMBOL',
    sub { Ham::RTTY::Decoder->new->decode('[FIGS] 01101') },
    'unassigned notation'
);
my $dec = Ham::RTTY::Decoder->new;
$dec->feed({unit => 'us', segments => [{state => 'mark', duration => 2**52}]});
error_is(
    'RTTY_E_RESOURCE',
    sub { $dec->feed({unit => 'us', segments => [{state => 'space', duration => 1}]}) },
    'cumulative duration'
);
my $complete = Ham::RTTY::Decoder->new->finish;
ok($complete->complete, 'empty decoder completes');
my $d = Ham::RTTY::Decoder->new;
$d->feed(
    {
        unit     => 'bits',
        baud     => 45.45,
        segments => [{state => 'space', duration => 0.2}, {state => 'mark', duration => 1}]
    }
);
is($d->finish->text, '', 'false start rejected at centre');
$d->reset->feed({unit => 'bits', baud => 45.45, segments => [{state => 'space', duration => 1}]});
is($d->finish->warnings->[0]{code}, 'RTTY_W_FRAMING', 'incomplete frame');
error_is('RTTY_E_STATE', sub { $d->feed({unit => 'us', segments => []}) }, 'decoder after finish');

for my $args (
    [min_frequency  => 2900],
    [min_frequency  => 2000, max_frequency => 1500],
    [frequency_step => 1],
    [atc            => 2],
    [search         => 2],
    [max_frames     => 0]
    )
{
    my $code = $args->[0] eq 'frequency_step' ? 'RTTY_E_RESOURCE' : 'RTTY_E_ARGUMENT';
    error_is($code, sub { Ham::RTTY::Detector->new(@{$args}) }, 'detector configuration');
}
my $short = Ham::RTTY::Detector->new(search => 1);
$short->feed([(0) x 100]);
is($short->finish->text,                   '', 'short acquisition finalization');
is(Ham::RTTY::Detector->new->finish->text, '', 'empty detector');
is(Ham::RTTY->new->decode_samples(Ham::RTTY->new->samples('CQ'), atc => 0)->text,
    'CQ', 'uncorrected tone comparison');
done_testing;
