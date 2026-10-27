use strict;
use warnings;
use Test::More;
use lib 't/lib';
use Reference qw(reference_sos);
use Ham::RTTY;
use Ham::RTTY::Events qw(to_samples);
my $samples = reference_sos();
my $base    = Ham::RTTY::Detector->new(sample_rate => 8000, frequency => 650, wpm => 20);
$base->feed($samples);
my $expected = $base->finish->as_hash;

for my $size (1, 7, 40, 127, 4096) {
    my $d = Ham::RTTY::Detector->new(sample_rate => 8000, frequency => 650, wpm => 20);
    for (my $i = 0; $i < @{$samples}; $i += $size) {
        my $end = $i + $size - 1;
        $end = $#{$samples} if $end > $#{$samples};
        $d->feed([@{$samples}[$i .. $end]]);
    }
    is_deeply($d->finish->as_hash, $expected, "detector block independence $size");
    is_deeply($d->finish->as_hash, $expected, 'finish does not duplicate partial frame');
}
my $events  = Ham::RTTY::Encoder->new->events('CQ TEST');
my $decoder = Ham::RTTY::Decoder->new(wpm => 20);
my $last    = '';
for my $segment (@{$events->{segments}}) {

    # Split each physical run over two feeds.
    my $first = int($segment->{duration} / 2);
    for my $duration ($first, $segment->{duration} - $first) {
        $decoder->feed(
            {unit => 'us', segments => [{state => $segment->{state}, duration => $duration}]});
        my $text = $decoder->result->text;
        is(substr($text, 0, length $last), $last, 'confirmed text is stable');
        $last = $text;
    }
}
is($decoder->finish->text, 'CQ TEST', 'split event stream');
is($decoder->finish->text, 'CQ TEST', 'idempotent event finish');
eval { $decoder->feed($events) };
is((ref($@) ? $@->code : "$@"), 'RTTY_E_STATE', 'post-finish decoder feed');
$decoder->reset;
$decoder->feed(to_samples($events, 11025));
is($decoder->finish->text, 'CQ TEST', 'sampled event decoding');
my $d = Ham::RTTY::Decoder->new(wpm => 20);
$d->feed({unit => 'us', segments => [{state => 'on', duration => 60000}]});
my $before = $d->result->as_hash;
eval { $d->feed({sample_rate => 16000, segments => []}) };
is((ref($@) ? $@->code : "$@"), 'RTTY_E_ARGUMENT', 'unit change rejected');
is_deeply($d->result->as_hash, $before, 'rejected feed preserves snapshot');
done_testing;
