#!/usr/bin/env perl
use 5.020;
use strict;
use warnings;
use lib 'lib';
use Ham::RTTY;
my ($path) = @ARGV;
die "Usage: build-corpus.pl NEW-SYNTHETIC.wav\n" unless defined $path;
Ham::RTTY->new(baud => 50, shift => 450)->write_wav('CQ TEST 123', $path);
print "Synthetic RTTY only: $path; this is not an off-air fixture.\n";
