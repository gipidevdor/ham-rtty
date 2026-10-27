#!/usr/bin/env perl
use 5.020;
use strict;
use warnings;
use Carp       qw(croak);
use File::Temp qw(tempdir);
use File::Spec;
use Ham::RTTY;
use Ham::RTTY::Events qw(to_timed);

my $directory = tempdir(CLEANUP => 1);
my $cw        = Ham::RTTY->new(wpm => 20, frequency => 650, sample_rate => 8000);
print 'Morse: ', $cw->encode('SOS'),         "\n";
print 'Text: ',  $cw->decode('... --- ...'), "\n";
my $events = $cw->sampled_events('SOS');
my $timed  = to_timed($events);
print 'Events: ', $cw->decode_events($timed, wpm => 20)->text, "\n";
my $samples = $cw->samples('SOS');
print 'Samples: ', $cw->decode_samples($samples, wpm => 20)->text, "\n";
my $wav = $cw->wav_bytes('SOS', bits => 24);
print 'WAV bytes: ',  $cw->decode_wav_bytes($wav)->text,          "\n";
print 'MIDI bytes: ', length($cw->midi_bytes('SOS', note => 77)), "\n";
my $path = File::Spec->catfile($directory, 'message.wav');
$cw->write_wav('SOS', $path);
print 'WAV file: ', $cw->read_wav($path)->text, "\n";
$cw->write_midi('SOS', File::Spec->catfile($directory, 'message.mid'));
my $audio    = Ham::RTTY::Audio->new(block_samples => 137);
my $detector = $cw->detector(wpm => 20);
$audio->read_blocks($path, sub { $detector->feed($_[0]); });
print 'Incremental reception: ', $detector->finish->text, "\n";
$detector->reset;
my $count = 0;
$count += $_->{samples} for @{$events->{segments}};
my $next = $cw->stream_samples('SOS', block_size => 137);
$audio->write_blocks(
    File::Spec->catfile($directory, 'stream.wav'), $next,
    sample_rate  => 8000,
    sample_count => $count
);
my $custom = File::Spec->catfile($directory, 'custom.mid');
Ham::RTTY::MIDI->new->write_file($custom, $events);
my $decoder = $cw->decoder(wpm => 20);
$decoder->feed($timed);
print 'Incremental events: ', $decoder->finish->text, "\n";
my $generator = $cw->generator;
my $generated = $generator->generate($events);
croak 'Sample count mismatch' unless @{$generated} == @{$samples};
my $raw = $audio->read_file($path);
$audio->write_file(File::Spec->catfile($directory, 'raw.wav'),
    $raw->{samples}, sample_rate => $raw->{sample_rate});
print "All workflows completed; temporary files are removed automatically.\n";
