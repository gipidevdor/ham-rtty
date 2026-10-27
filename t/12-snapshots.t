use 5.020;
use strict;
use warnings FATAL => 'all';
use Test::More;
use Ham::RTTY;
use Ham::RTTY::_Internal::Data qw(plain_data);

sub rejects {
    my ($class, @args) = @_;
    ok(!eval { $class->new(@args); 1 }, "$class rejects invalid payload");
    isa_ok($@, 'Ham::RTTY::Error');
}
for my $class ('Ham::RTTY::Error', 'Ham::RTTY::Result') {
    rejects($class, 'odd');
    rejects($class, undef, 1);
    rejects($class, [],    1);
    rejects($class, unexpected => 1);
    my $key = $class eq 'Ham::RTTY::Error' ? 'message' : 'text';
    rejects($class, $key => 'first', $key => 'duplicate');
    rejects($class, $key => undef);
    rejects($class, $key => []);
}
my $cycle = {};
$cycle->{cycle} = $cycle;
my $deep = {};
$deep = {next => $deep} for 1 .. 66;
my $scalar = 1;
for my $bad (
    $cycle, $deep,
    bless({}, 'ForeignObject'),
    {scalar   => \$scalar},
    {function => sub { return }}
    )
{
    ok(!plain_data($bad), 'unsafe payload rejected');
    rejects('Ham::RTTY::Error',  context     => $bad);
    rejects('Ham::RTTY::Result', diagnostics => $bad);
}
rejects('Ham::RTTY::Error', context => []);
rejects('Ham::RTTY::Error', code    => undef);
rejects('Ham::RTTY::Error', code    => []);
for my $args (
    [notation    => undef],
    [notation    => []],
    [frequency   => -1],
    [baud        => 'Inf'],
    [complete    => 2],
    [events      => []],
    [warnings    => {}],
    [diagnostics => []],
    [warnings    => [undef]],
    [warnings    => [{code => [], message => 'x'}]],
    [warnings    => [{code => 'x'}]],
    [warnings    => [{code => 'x', message => []}]],
    [warnings    => [{code => 'x', message => undef}]]
    )
{
    rejects('Ham::RTTY::Result', @{$args});
}
my $shared = {value => [1]};
ok(plain_data({first => $shared, second => $shared}), 'shared children are valid');
my $e = Ham::RTTY::Error->new(code => 'RTTY_E_TEST', message => 'test', context => $shared);
is($e->code,    'RTTY_E_TEST',       'error code');
is($e->message, 'test',              'message');
is("$e",        'RTTY_E_TEST: test', 'error string');
my $ctx = $e->context;
$ctx->{value}[0] = 99;
is($e->context->{value}[0],        1,                   'error deep copy');
is(Ham::RTTY::Error->new->code,    'RTTY_E_INTERNAL',   'default error');
is(Ham::RTTY::Error->new->message, 'Unspecified error', 'default message');
my $r = Ham::RTTY::Result->new(
    text        => 'A',
    notation    => '00011',
    frequency   => 2125,
    baud        => 50,
    warnings    => [{code => 'RTTY_W_TEST', message => 'test'}],
    complete    => 1,
    diagnostics => $shared
);
is($r->text,      'A',     'text accessor');
is($r->notation,  '00011', 'notation accessor');
is($r->frequency, 2125,    'frequency accessor');
is($r->baud,      50,      'baud accessor');
ok($r->has_text && $r->has_warnings && $r->complete, 'predicates');
$r->warnings->[0]{code} = 'changed';
is($r->warnings->[0]{code}, 'RTTY_W_TEST', 'warning deep copy');
$r->diagnostics->{value}[0] = 99;
is($r->diagnostics->{value}[0], 1, 'diagnostics deep copy');
$r->as_hash->{text} = 'changed';
is($r->text, 'A', 'whole snapshot deep copy');
ok(!Ham::RTTY::Result->new->has_text && !Ham::RTTY::Result->new->has_warnings, 'empty predicates');
my $codec = Ham::RTTY::Baudot->new;
$codec->tables->{letters}[3] = 'changed';
is($codec->character(3), 'A', 'table copy');
my $d = Ham::RTTY::Decoder->new;
$d->feed({unit => 'us', segments => [{state => 'mark', duration => 1000}]});
$d->feed({unit => 'us', segments => [{state => 'mark', duration => 1000}]});
is(scalar @{$d->result->events->{segments}}, 1, 'adjacent same-state feeds merged');
my $rtty    = Ham::RTTY->new;
my $det     = $rtty->detector;
my $preview = $det->result;
is($det->result, $preview, 'cached detector preview');
ok(!eval { $det->feed([2]); 1 }, 'rejected feed');
is($det->result, $preview, 'rejected feed preserves cache');
$det->feed($rtty->samples('CQ'));
isnt($det->result, $preview, 'accepted feed invalidates preview');
is($det->finish->text, 'CQ',         'preview does not consume samples');
is($det->finish,       $det->result, 'idempotent finish');
done_testing;
