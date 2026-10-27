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
my $rtty      = Ham::RTTY->new(baud => 50, mark => 650, sample_rate => 8000);
print 'Notation: ', $rtty->encode('SOS'),                "\n";
print 'Text: ',     $rtty->decode($rtty->encode('SOS')), "\n";
my $events = $rtty->sampled_events('SOS');
my $timed  = to_timed($events);
print 'Events: ', $rtty->decode_events($timed, baud => 50)->text, "\n";
my $samples = $rtty->samples('SOS');
print 'Samples: ', $rtty->decode_samples($samples, mark => 650, baud => 50)->text, "\n";
my $wav = $rtty->wav_bytes('SOS', bits => 24);
print 'WAV bytes: ',  $rtty->decode_wav_bytes($wav, mark => 650, baud => 50)->text,        "\n";
print 'MIDI bytes: ', length($rtty->midi_bytes('SOS', mark_note => 77, space_note => 79)), "\n";
my $path = File::Spec->catfile($directory, 'message.wav');
$rtty->write_wav('SOS', $path);
print 'WAV file: ', $rtty->read_wav($path, mark => 650, baud => 50)->text, "\n";
$rtty->write_midi('SOS', File::Spec->catfile($directory, 'message.mid'));
my $audio    = Ham::RTTY::Audio->new(block_samples => 137);
my $detector = $rtty->detector(mark => 650, baud => 50);
$audio->read_blocks($path, sub { $detector->feed($_[0]); });
print 'Incremental reception: ', $detector->finish->text, "\n";
$detector->reset;
my $count = 0;
$count += $_->{samples} for @{$events->{segments}};
my $next = $rtty->stream_samples('SOS', block_size => 137);
$audio->write_blocks(
    File::Spec->catfile($directory, 'stream.wav'), $next,
    sample_rate  => 8000,
    sample_count => $count
);
my $custom = File::Spec->catfile($directory, 'custom.mid');
Ham::RTTY::MIDI->new->write_file($custom, $events);
my $decoder = $rtty->decoder(baud => 50);
$decoder->feed($timed);
print 'Incremental events: ', $decoder->finish->text, "\n";
my $generator = $rtty->generator;
my $generated = $generator->generate($events);
croak 'Sample count mismatch' unless @{$generated} == @{$samples};
my $raw = $audio->read_file($path);
$audio->write_file(File::Spec->catfile($directory, 'raw.wav'),
    $raw->{samples}, sample_rate => $raw->{sample_rate});
print "All workflows completed; temporary files are removed automatically.\n";
