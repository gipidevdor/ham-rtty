#!/usr/bin/env perl
use 5.020;
use strict;
use warnings;
use Carp qw(croak);
use Ham::RTTY;
use Ham::RTTY::Detector;

my $backend  = shift @ARGV // 'perl';
my $rtty     = Ham::RTTY->new(sample_rate => 8000, baud => 50, backend => $backend);
my $samples  = $rtty->samples('CQ 123');
my %options  = (sample_rate => 8000, baud => 50, backend => $backend);
my $detector = Ham::RTTY::Detector->new(%options);
print 'Detector initial state: ', $detector->state, "\n";
for (my $offset = 0; $offset < @{$samples}; $offset += 137) {
    my $end = $offset + 136;
    $end = $#{$samples} if $end > $#{$samples};
    $detector->feed([@{$samples}[$offset .. $end]]);
}
my $preview = $detector->result;
my $final   = $detector->finish;
croak 'Incremental reception failed' unless $final->text eq 'CQ 123';
croak 'Preview was changed by finish' if $preview->complete;
croak 'Collected reception failed'
    unless $rtty->decode_samples($samples, %options)->text eq $final->text;
$detector->reset;
croak 'Reset failed' unless $detector->state eq 'READY';
my $factory = $rtty->detector(baud => 50);
$factory->feed($samples);
croak 'Factory reception failed' unless $factory->finish->text eq $final->text;
print 'Text: ', $final->text, "\nExample completed: reception-samples\n";
