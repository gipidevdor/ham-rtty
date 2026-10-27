#!/usr/bin/env perl
use 5.020;
use strict;
use warnings;
use Carp       qw(croak);
use File::Temp qw(tempdir);
use File::Spec;
use Ham::RTTY;
use Ham::RTTY::Audio;
use Ham::RTTY::Detector;

my $backend = shift @ARGV // 'perl';
my $cw      = Ham::RTTY->new(sample_rate => 8000, wpm => 20, backend => $backend);
my $strong  = $cw->samples('SOS', frequency => 650, amplitude => 0.4);
my $weak    = $cw->samples('CQ',  frequency => 950, amplitude => 0.2);
my $known   = $cw->decode_samples($strong, frequency => 650, wpm => 20);
croak 'Known tone not recovered' unless $known->text eq 'SOS';
my $spaced   = $cw->samples('CQ CQ', frequency => 650, effective_wpm => 12);
my $practice = $cw->decode_samples($spaced, frequency => 650, wpm => 20, effective_wpm => 12);
croak 'Farnsworth audio not recovered' unless $practice->text eq 'CQ CQ';
my $count = @{$strong} > @{$weak} ? @{$strong} : @{$weak};
my @mixed =
    ((0) x 400, (map { ($strong->[$_] // 0) + ($weak->[$_] // 0) } 0 .. $count - 1), (0) x 400);
my %search = (
    wpm              => 20,
    min_frequency    => 600,
    max_frequency    => 1000,
    frequency_step   => 50,
    filter_bandwidth => 100,
    min_snr_db       => 12
);
my $detector = Ham::RTTY::Detector->new(sample_rate => 8000, backend => $backend, %search);
print 'Detector initial state: ', $detector->state, "\n";

for (my $offset = 0; $offset < @mixed; $offset += 997) {
    my $end = $offset + 996 < $#mixed ? $offset + 996 : $#mixed;
    $detector->feed([@mixed[$offset .. $end]]);
}
my $preview = $detector->result;
print 'Preview is complete: ', $preview->complete, "\n";
my $primary  = $detector->finish;
my $channels = $detector->channels;
my %heard    = map { $_->text => 1 } @{$channels};
croak 'Expected two messages' unless $heard{SOS} && $heard{CQ};
for my $station (@{$channels}) {
    printf "%.1f Hz: %s (%d warnings)\n", $station->frequency, $station->text,
        scalar(@{$station->warnings});
}
croak 'Final preview differs' unless $detector->result->text eq $primary->text;
$detector->reset;
croak 'Detector reset failed' unless $detector->state eq 'READY';

my $all = $cw->decode_samples_channels(\@mixed, %search);
croak 'Array channel reception failed' if @{$all} < 2;
my $directory = tempdir(CLEANUP => 1);
my $path      = File::Spec->catfile($directory, 'two-stations.wav');
Ham::RTTY::Audio->new(backend => $backend)->write_file($path, \@mixed, sample_rate => 8000);
my $from_path = $cw->read_wav_channels($path, %search);
open my $in, '<:raw', $path or croak $!;
my $from_handle = $cw->decode_wav_channels($in, %search, block_samples => 997);
close $in or croak $!;
croak 'File channel reception failed' if @{$from_path} < 2 || @{$from_handle} < 2;

# Omitting tone AND speed estimates both, independently of generation settings.
my $automatic = $cw->detector(min_frequency => 600, max_frequency => 700, frequency_step => 50);
$automatic->feed($strong);
print 'Estimated speed: ', $automatic->finish->wpm // 'unknown', " WPM\n";
my $silent = Ham::RTTY::Detector->new(sample_rate => 8000, backend => $backend, %search);
$silent->feed([(0) x 8000]);
my $empty = $silent->finish;
croak 'Silence should not decode' if $empty->has_text;
print 'Silence warnings: ', scalar(@{$empty->warnings}), "\n";
print "Example completed: reception-channels\n";
