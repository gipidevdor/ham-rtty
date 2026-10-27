#!/usr/bin/env perl
use 5.020;
use strict;
use warnings;
use Carp qw(croak);
use JSON::PP;
use Ham::RTTY;
use Ham::RTTY::Result;
binmode STDOUT, ':encoding(UTF-8)' or croak $!;

my $cw       = Ham::RTTY->new;
my $received = $cw->decode_events($cw->events('SOS'), wpm => 20);
my $copy     = $received->as_hash;
my $snapshot = Ham::RTTY::Result->new(%{$copy},);
print 'Text: ', $snapshot->text, "\nMorse: ", $snapshot->morse, "\n";
print 'Complete: ', $snapshot->complete, '; has text: ', $snapshot->has_text,
    '; warnings: ', $snapshot->has_warnings, "\n";
print 'Speed: ', $snapshot->wpm // 'unknown', '; frequency: ',
    $snapshot->frequency // 'not measured', "\n";
print 'Events: ',      scalar(@{$snapshot->events->{segments}}),                 " runs\n";
print 'Diagnostics: ', JSON::PP->new->canonical->encode($snapshot->diagnostics), "\n";
for my $warning (@{$snapshot->warnings}) { print "$warning->{code}: $warning->{message}\n" }
$copy->{text} = 'Changed outside the snapshot';
my $events = $snapshot->events;
$events->{segments} = [];
croak 'Snapshot was mutated' unless $snapshot->text eq 'SOS' && @{$snapshot->events->{segments}};
my $empty = Ham::RTTY::Result->new;
croak 'Empty snapshot has text' if $empty->has_text;
print JSON::PP->new->canonical->encode($snapshot->as_hash), "\n";
print "Completion and nonempty text are not accuracy guarantees.\nExample completed: results\n";
