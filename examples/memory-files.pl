#!/usr/bin/env perl
use 5.020;
use strict;
use warnings;
use Carp       qw(croak);
use File::Temp qw(tempdir);
use File::Spec;
use Ham::RTTY;

my $backend = shift @ARGV // 'perl';
my $rtty    = Ham::RTTY->new(sample_rate => 8000, mark => 650, baud => 50, backend => $backend);
my %hints   = (mark => 650, baud => 50);
my $bytes   = $rtty->wav_bytes('SOS', bits => 16);
croak 'Memory WAV decode failed' unless $rtty->decode_wav_bytes($bytes, %hints)->text eq 'SOS';
print 'Collected WAV bytes: ', length($bytes), "\n";

# Scalar handles use the same public handle API as disk files.
my $streamed = '';
open my $out, '>:raw', \$streamed or croak $!;
my $stats = $rtty->generate_wav('SOS', $out, bits => 24, block_size => 137);
close $out or croak $!;
open my $in, '<:raw', \$streamed or croak $!;
my $result = $rtty->decode_wav($in, %hints, block_samples => 101);
close $in or croak $!;
croak 'Handle WAV decode failed' unless $result->text eq 'SOS';
print "Streamed samples: $stats->{samples}; result: ", $result->text, "\n";

my $directory = tempdir(CLEANUP => 1);
my $path      = File::Spec->catfile($directory, 'practice.wav');
$rtty->write_wav('SOS', $path, bits => 8);
croak 'Path decode failed' unless $rtty->read_wav($path, %hints)->text eq 'SOS';
$rtty->write_wav('CQ', $path, bits => 24, overwrite => 1);
croak 'Explicit replacement failed' unless $rtty->read_wav($path, %hints)->text eq 'CQ';
print "Named WAV replaced explicitly; temporary directory will be removed.\n";
print "Example completed: memory-files\n";
