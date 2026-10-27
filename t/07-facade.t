use strict;
use warnings;
use Test::More;
use Ham::RTTY;
my $cw = Ham::RTTY->new;
for my $bits (8, 16, 24) {
    my $bytes = '';
    open my $out, '>', \$bytes or die $!;
    $cw->generate_wav('CQ DE TESTCALL', $out, bits => $bits);
    close $out;
    open my $in, '<', \$bytes or die $!;
    my $r = $cw->decode_wav($in, frequency => 700, wpm => 20);
    is($r->text, 'CQ DE TESTCALL', "WAV facade $bits bits");
}
my $events = {unit => 'us', segments => []};
my $r      = Ham::RTTY::Result->new(
    text        => 'TEST',
    events      => $events,
    warnings    => [],
    diagnostics => {a => 1}
);
$events->{segments}[0] = {state => 'on', duration => 1};
is_deeply($r->events, {unit => 'us', segments => []}, 'copy inputs');
my $h = $r->as_hash;
$h->{text} = 'BAD';
is($r->text, 'TEST', 'copy all fields');
my $diagnostics = $r->diagnostics;
$diagnostics->{a} = 2;
is($r->diagnostics->{a}, 1, 'copy diagnostics');
eval { $r->{text} = 'BAD' };
ok($@, 'locked top-level result');
my $error = Ham::RTTY::Error->new(
    code    => 'RTTY_E_ARGUMENT',
    message => 'Bad option',
    context => {parameter => 'x'}
);
is("$error", 'RTTY_E_ARGUMENT: Bad option', 'exception string overload');
my $ctx = $error->context;
$ctx->{parameter} = 'y';
is($error->context->{parameter}, 'x', 'exception context copied');

for my $args ({typo => 20}, {wpm => 0}, {effective_wpm => 21}, {frequency => 'Inf'}) {
    eval { Ham::RTTY->new(%{$args}) };
    is((ref($@) ? $@->code : "$@"), 'RTTY_E_ARGUMENT', 'facade rejects invalid configuration');
}
done_testing;
