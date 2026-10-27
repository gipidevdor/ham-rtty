#!/usr/bin/env perl
use 5.020;
use strict;
use warnings;
use Ham::RTTY;
use Getopt::Long qw(GetOptions);
my $backend = 'perl';
GetOptions('backend=s' => \$backend) or die "Invalid options\n";
my $rtty   = Ham::RTTY->new(backend => $backend);
my $result = $rtty->decode_wav_bytes($rtty->wav_bytes('CQ 123'), backend => $backend);
die "Round trip failed\n" unless $result->text eq 'CQ 123';
print "$backend examples PASS\n";
