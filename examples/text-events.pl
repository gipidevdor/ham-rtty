#!/usr/bin/env perl
use 5.020;
use strict;
use warnings;
use Ham::RTTY;
my $rtty = Ham::RTTY->new(baud => 50);
print $rtty->encode('CQ 123'), "\n";
my $result = $rtty->decode_events($rtty->events('CQ 123'), baud => 50);
die "Event round trip failed\n" unless $result->text eq 'CQ 123';
print $result->text, "\n";
