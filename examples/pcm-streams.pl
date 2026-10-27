#!/usr/bin/env perl
use 5.020;
use strict;
use warnings;
use Carp       qw(croak);
use File::Temp qw(tempdir);
use File::Spec;
use Ham::RTTY::Audio;

my $backend   = shift @ARGV // 'perl';
my $audio     = Ham::RTTY::Audio->new(backend => $backend, block_samples => 2);
my $directory = tempdir(CLEANUP => 1);
my $samples   = [-1, -0.25, 0, 0.25, 1];
for my $bits (8, 16, 24) {
    my $path = File::Spec->catfile($directory, "pcm-$bits.wav");
    $audio->write_file($path, $samples, sample_rate => 8000, bits => $bits);
    my $recording = $audio->read_file($path);
    croak 'Wrong PCM frame count' unless @{$recording->{samples}} == @{$samples};
    print "$bits-bit PCM: ", scalar(@{$recording->{samples}}), " frames\n";
}

my $path   = File::Spec->catfile($directory, 'blocks.wav');
my @blocks = ([@{$samples}[0, 1]], [@{$samples}[2 .. 4]]);
$audio->write_blocks($path, sub { return shift @blocks }, sample_rate => 8000, sample_count => 5);
my $count    = 0;
my $metadata = $audio->read_blocks(
    $path,
    sub {
        my ($block, $info) = @_;
        $count += @{$block};
        croak 'Unexpected rate' unless $info->{sample_rate} == 8000;
    }
);
croak 'Callback count differs' unless $count == $metadata->{sample_count};
open my $in, '<:raw', $path or croak $!;
my $reader = $audio->reader($in);
my $pulled = 0;
while (my $block = $reader->{next}->()) { $pulled += @{$block} }
close $in or croak $!;
croak 'Pull reader count differs' unless $pulled == $count;

my $bytes = '';
open my $out, '>:raw', \$bytes or croak $!;
my $writer = $audio->writer($out, sample_rate => 8000, sample_count => 5, bits => 24);
print 'Writer initial state: ', $writer->state, "\n";
$writer->feed([@{$samples}[0, 1]]);
print 'Writer progress: ', $writer->result->{samples}, " frames\n";
$writer->feed([@{$samples}[2 .. 4]]);
my $final = $writer->finish;
croak 'Repeated finish changed count' unless $writer->finish->{samples} == $final->{samples};
close $out or croak $!;
open $in, '<:raw', \$bytes or croak $!;
my $collected = $audio->read($in);
close $in or croak $!;
my $copy = '';
open $out, '>:raw', \$copy or croak $!;
$audio->write($out, $collected->{samples}, sample_rate => 8000, bits => 16);
close $out or croak $!;

# Input can be stereo, although public WAV output is mono. This tiny
# independently assembled PCM fixture has left=0.25 and right=0.75.
my $payload = pack('s<*', (8192, 24576) x 5);
my $stereo  = 'RIFF'
    . pack('V', 36 + length($payload))
    . 'WAVEfmt '
    . pack('VvvVVvv', 16, 1, 2, 8000, 32000, 4, 16) . 'data'
    . pack('V', length($payload))
    . $payload;
for my $selection (['left', 0.25], ['right', 0.75], ['mix', 0.5]) {
    open $in, '<:raw', \$stereo or croak $!;
    my $recording = Ham::RTTY::Audio->new(backend => $backend, stereo => $selection->[0])->read($in);
    close $in or croak $!;
    croak 'Stereo selection differs' if abs($recording->{samples}[0] - $selection->[1]) > 0.0001;
    print "$selection->[0]: $recording->{samples}[0]\n";
}
print "Example completed: pcm-streams\n";
