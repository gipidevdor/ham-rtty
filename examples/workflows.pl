#!/usr/bin/env perl
use 5.020;
use strict;
use warnings;
use Ham::RTTY;
my $rtty   = Ham::RTTY->new;
my $wav    = $rtty->wav_bytes('CQ TEST 123');
my $result = $rtty->decode_wav_bytes($wav, baud => 45.45);
die "Round trip failed\n" unless $result->text eq 'CQ TEST 123';
print $result->text, "\n";
