use strict;
use warnings;
use Test::More;
use Ham::RTTY;
use lib 't/lib';
use Reference qw(reference_sos);

for my $class ('Ham::RTTY::Decoder', 'Ham::RTTY::Detector') {
    my $object =
          $class eq 'Ham::RTTY::Decoder'
        ? $class->new(wpm         => 20)
        : $class->new(sample_rate => 8000, frequency => 650, wpm => 20);
    my $empty = $object->result;
    is($object->result, $empty, "$class reuses unchanged snapshot");
    eval { $object->feed(undef) };
    ok($@, "$class rejects invalid input");
    is($object->result, $empty, "$class invalid feed preserves cache");
    my $input = $class eq 'Ham::RTTY::Decoder' ? Ham::RTTY->new->events('SOS') : reference_sos();
    $object->feed($input);
    my $active = $object->result;
    isnt($active, $empty, "$class successful feed invalidates cache");
    is($object->result, $active, "$class active snapshot reused");
    ok(!$active->complete, "$class provisional snapshot");
    my $events = $active->events;
    $events->{segments}[0]{state} = 'changed';
    isnt($object->result->events->{segments}[0]{state}, 'changed', "$class accessor isolated");
    my $final = $object->finish;
    is($final->text, 'SOS', "$class final text");
    ok($final->complete, "$class final snapshot");
    is($object->finish, $final, "$class finish reuses final snapshot");
    is($object->result, $final, "$class result returns final snapshot");
    ok(!$active->complete, "$class old snapshot preserved");
    $object->reset;
    my $reset = $object->result;
    isnt($reset, $final, "$class reset invalidates cache");
    is_deeply($reset->as_hash, $empty->as_hash, "$class reset restores empty state");
}
my $partial = Ham::RTTY::Detector->new(sample_rate => 8000, frequency => 650);
$partial->feed([(0) x 40]);
my $before = $partial->result;
$partial->feed([0]);
my $after = $partial->result;
isnt($before, $after, 'partial-frame feed invalidates snapshot');
is_deeply($before->as_hash, $after->as_hash, 'partial frame remains excluded until finish');
$partial->finish;
is($partial->result->events->{sample_rate}, 8000, 'partial frame finalizes on original grid');
done_testing;
