#!/usr/bin/env perl
use 5.020;
use strict;
use warnings;
use Carp       qw(croak);
use File::Temp qw(tempdir);
use File::Spec;
use Ham::RTTY;
use Ham::RTTY::MIDI;

my $cw       = Ham::RTTY->new(wpm => 20, sample_rate => 8000);
my %settings = (note => 77, velocity => 90, channel => 2, program => 80, bpm => 90, ppqn => 960);
my $midi     = Ham::RTTY::MIDI->new(%settings);
my $timed    = $cw->events('SOS');
my $sampled  = $cw->sampled_events('SOS');
my $bytes    = $midi->encode($timed);
croak 'Expected SMF header'            unless substr($bytes, 0, 4) eq 'MThd';
croak 'Exact sampled schedule differs' unless $midi->encode($sampled) eq $bytes;
my $handle_bytes = '';
open my $out, '>:raw', \$handle_bytes or croak $!;
my $written = $midi->write($out, $timed);
close $out or croak $!;
croak 'Handle MIDI differs' unless $handle_bytes eq $bytes && $written == length($bytes);

my $directory = tempdir(CLEANUP => 1);
my $path      = File::Spec->catfile($directory, 'custom.mid');
$midi->write_file($path, $timed);
$midi->write_file($path, $sampled, overwrite => 1);
my $facade    = $cw->midi_bytes('SOS', %settings);
my $generated = '';
open $out, '>:raw', \$generated or croak $!;
$cw->generate_midi('SOS', $out, %settings);
close $out or croak $!;
croak 'Facade MIDI differs' unless $generated eq $facade && $facade eq $bytes;
$cw->write_midi('SOS', File::Spec->catfile($directory, 'facade.mid'), %settings);
print 'MIDI bytes: ', length($bytes), "; channel 2, program 80, 960 PPQN\n";
print "WPM controls Morse timing; BPM maps that timing to MIDI ticks.\n";
print "Example completed: midi-paths\n";
