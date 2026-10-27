#!/usr/bin/env perl
use 5.020;
use strict;
use warnings;
use Ham::RTTY;
my ($path) = @ARGV;
die "Usage: receive.pl INPUT.wav\n" unless defined $path;
my $result = Ham::RTTY->new->read_wav($path, baud => 45.45);
print $result->text, "\n";
warn "$_->{code}: $_->{message}\n" for @{$result->warnings};
