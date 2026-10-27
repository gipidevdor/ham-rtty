#!/usr/bin/env perl
use 5.020;
use strict;
use warnings;
use Ham::RTTY;
my ($path, @words) = @ARGV;
die "Usage: send.pl OUTPUT.wav TEXT\n" unless defined $path;
Ham::RTTY->new->write_wav(join(' ', @words), $path);
print "Wrote $path\n";
