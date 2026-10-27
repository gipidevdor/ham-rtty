#!/usr/bin/env perl
use 5.020;
use strict;
use warnings;
use utf8;
use Carp qw(croak);
use Ham::RTTY;
use Ham::RTTY::Encoder;
use Ham::RTTY::Decoder;
use Ham::RTTY::Events qw(validate_events to_samples to_timed);
binmode STDOUT, ':encoding(UTF-8)' or croak $!;

my $cw            = Ham::RTTY->new(wpm => 20);
my $configuration = Ham::RTTY::Encoder->validate(wpm => 20, effective_wpm => 12);
my $encoder       = Ham::RTTY::Encoder->new(%{$configuration});
my $decoder       = Ham::RTTY::Decoder->new(wpm => 20, effective_wpm => 12);
my $morse         = $encoder->encode('CQ DE TESTCALL');
print "Notation: $morse\nText: ", $decoder->decode($morse), "\n";
croak 'Unexpected text' unless $cw->decode($cw->encode('SOS')) eq 'SOS';
print 'Empty input: [',            $cw->encode(''),                               "]\n";
print 'Skip unsupported symbol: ', $cw->encoder(unknown => 'skip')->encode('A!'), "\n";

# Shared waveforms recover a canonical spelling, not the original token.
my $aliases = $encoder->encode('é × + <AR> <BT>');
print 'Canonical symbols: ', $cw->decode($aliases),                                "\n";
print 'Prefer signals: ',    $cw->decoder(prefer_prosigns => 1)->decode($aliases), "\n";

my $timed   = $encoder->events('CQ TEST');
my $sampled = to_samples($timed, 8000);
my $again   = to_timed($sampled);
print 'Event fields: ', validate_events($timed), ', ', validate_events($sampled), "\n";
croak 'Wrong converted unit' unless $again->{unit} eq 'us';
my $facade_timed   = $cw->events('SOS');
my $facade_sampled = $cw->sampled_events('SOS', sample_rate => 8000);
croak 'Wrong facade events' unless validate_events($facade_sampled) eq 'samples';
print 'Event decode: ', $cw->decode_events($facade_timed, wpm => 20)->text, "\n";
croak 'Sampled event decode failed'
    unless $cw->decode_events($facade_sampled, wpm => 20)->text eq 'SOS';

# A sampled mark split across feed boundaries is joined into one mark.
my $joined = $cw->decoder(wpm => 20);
$joined->feed({sample_rate => 8000, segments => [{state => 'on', samples => 240}]});
$joined->feed({sample_rate => 8000, segments => [{state => 'on', samples => 240}]});
croak 'Split mark was not joined' unless $joined->finish->text eq 'E';

# Every feed is a valid block. Results are cumulative, not text deltas.
print 'Decoder initial state: ', $decoder->state, "\n";
for my $segment (@{$timed->{segments}}) {
    $decoder->feed({unit => 'us', segments => [$segment]});
}
my $preview = $decoder->result;
print 'Provisional: ', $preview->complete, "\n";
my $final = $decoder->finish;
croak 'Farnsworth text lost' unless $final->text eq 'CQ TEST';
print 'Finished: ', $final->text, ' / ', $decoder->state, "\n";
$decoder->reset;
croak 'Reset failed' unless $decoder->state eq 'READY' && $final->text eq 'CQ TEST';
print "Example completed: text-events\n";
