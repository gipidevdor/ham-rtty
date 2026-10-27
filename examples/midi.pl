#!/usr/bin/env perl
use 5.020;
use strict;
use warnings;
use Ham::RTTY;
my ($path, @words) = @ARGV;
die "Usage: midi.pl OUTPUT.mid TEXT\n" unless defined $path;
Ham::RTTY->new->write_midi(join(' ', @words), $path);
print "Wrote $path\n";
