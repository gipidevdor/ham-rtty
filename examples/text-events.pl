#!/usr/bin/env perl
use 5.020;
use strict;
use warnings;
use utf8;
use Carp qw(croak);
use Ham::RTTY;
use Ham::RTTY::Encoder;
use Ham::RTTY::Baudot;
use Ham::RTTY::Decoder;
use Ham::RTTY::Events qw(validate_events to_samples to_timed);
binmode STDOUT, ':encoding(UTF-8)' or croak $!;

my $rtty          = Ham::RTTY->new(baud => 50);
my $configuration = Ham::RTTY::Encoder->validate(baud => 50, stop_bits => 1.5);
my $encoder       = Ham::RTTY::Encoder->new(%{$configuration});
my $decoder       = Ham::RTTY::Decoder->new(baud => 50);
my $notation      = $encoder->encode('CQ DE TESTCALL');
print "Notation: $notation\nText: ", $decoder->decode($notation), "\n";
croak 'Unexpected text' unless $rtty->decode($rtty->encode('SOS')) eq 'SOS';
print 'Empty input: [',                  $rtty->encode(''),                          "]\n";
print 'Substitute unsupported symbol: ', $rtty->encoder(lenient => 1)->encode('A!'), "\n";

# ITA2 shifts and USOS are explicit transmitter/receiver settings.
my $figures = $encoder->encode('1 2');
croak 'USOS round trip failed' unless $rtty->decode($figures) eq '1 2';
my $frames = $encoder->frames('A');
croak 'Unexpected LSB order' unless $frames->[1]{data_bits} eq '11000';
my $bits = $encoder->bits('CQ');
croak 'Bit decode failed' unless $rtty->decoder(baud => 50)->decode_bits($bits)->text eq 'CQ';
print 'Facade bits: ',       $rtty->bits('A'),                      "\n";
print 'Encoding warnings: ', scalar(@{$encoder->result->warnings}), "\n";
my $codec = Ham::RTTY::Baudot->new;
croak 'Unexpected table'     unless $codec->tables->{letters}[3] eq 'A';
croak 'Unexpected character' unless $codec->character(3) eq 'A';
$codec->reset;

my $timed   = $encoder->events('CQ TEST');
my $sampled = to_samples($timed, 8000);
my $again   = to_timed($sampled);
print 'Event fields: ', validate_events($timed), ', ', validate_events($sampled), "\n";
croak 'Wrong converted unit' unless $again->{unit} eq 'us';
my $facade_timed   = $rtty->events('SOS');
my $facade_sampled = $rtty->sampled_events('SOS', sample_rate => 8000);
croak 'Wrong facade events' unless validate_events($facade_sampled) eq 'samples';
print 'Event decode: ', $rtty->decode_events($facade_timed, baud => 50)->text, "\n";
croak 'Sampled event decode failed'
    unless $rtty->decode_events($facade_sampled, baud => 50)->text eq 'SOS';

# Split a MARK across feeds; the decoder joins adjacent boundary states.
my $joined = $rtty->decoder(baud => 50);
my @runs   = @{$facade_sampled->{segments}};
my $first  = shift @runs;
my $half   = int($first->{samples} / 2);
$joined->feed({sample_rate => 8000, segments => [{state => $first->{state}, samples => $half}]});
$joined->feed(
    {
        sample_rate => 8000,
        segments    => [{state => $first->{state}, samples => $first->{samples} - $half}, @runs]
    }
);
croak 'Split run was not joined' unless $joined->finish->text eq 'SOS';

# Every feed is a valid block. Results are cumulative, not text deltas.
print 'Decoder initial state: ', $decoder->state, "\n";
for my $segment (@{$timed->{segments}}) {
    $decoder->feed({unit => 'us', segments => [$segment]});
}
my $preview = $decoder->result;
print 'Provisional: ', $preview->complete, "\n";
my $final = $decoder->finish;
croak 'Framed text lost' unless $final->text eq 'CQ TEST';
print 'Finished: ', $final->text, ' / ', $decoder->state, "\n";
$decoder->reset;
croak 'Reset failed' unless $decoder->state eq 'READY' && $final->text eq 'CQ TEST';
print "Example completed: text-events\n";
