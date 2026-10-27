#!/usr/bin/env perl
use 5.020;
use strict;
use warnings;
use lib 'lib';
use Carp qw(croak);
use Config;
use Getopt::Long qw(GetOptions);
use JSON::PP;
use Time::HiRes qw(time);
use Ham::RTTY;
use Ham::RTTY::Generator;
use Ham::RTTY::Detector;
use Ham::RTTY::Audio;
use Ham::RTTY::_Internal::PDL;

sub write_wav {
    my ($samples, $rate, $bits, $backend) = @_;
    my $bytes = '';
    open my $fh, '>:raw', \$bytes or croak $!;
    Ham::RTTY::Audio->new(backend => $backend)->write(
        $fh, $samples,
        sample_rate => $rate,
        bits        => $bits
    );
    close $fh or croak $!;
    return $bytes;
}

sub read_wav {
    my ($bytes, $backend) = @_;
    open my $fh, '<:raw', \$bytes or croak $!;
    my $result = Ham::RTTY::Audio->new(backend => $backend)->read($fh);
    close $fh or croak $!;
    return $result;
}

sub detect {
    my ($samples, $rate, $backend, $size) = @_;
    my $detector = Ham::RTTY::Detector->new(sample_rate => $rate, backend => $backend);
    for (my $i = 0; $i < @{$samples}; $i += $size) {
        my $end = $i + $size - 1;
        $end = $#{$samples} if $end > $#{$samples};
        $detector->feed([@{$samples}[$i .. $end]]);
    }
    return $detector->finish;
}

sub cases {
    my ($events, $samples, $rate) = @_;
    my $pcm = [@{$samples}[0 .. $rate - 1]];
    my %cases;
    for my $backend (qw(perl pdl)) {
        $cases{generate}{$backend} = sub {
            Ham::RTTY::Generator->new(sample_rate => $rate, backend => $backend)->generate($events);
        };
        $cases{detect}{$backend} = sub { detect($samples, $rate, $backend, scalar @{$samples}) };
        $cases{detect_stream}{$backend} = sub { detect($samples, $rate, $backend, 4096) };
        for my $bits (8, 16, 24) {
            my $bytes = write_wav($pcm, $rate, $bits, 'perl');
            $cases{"wav_read_$bits"}{$backend}  = sub { read_wav($bytes, $backend) };
            $cases{"wav_write_$bits"}{$backend} = sub { write_wav($pcm, $rate, $bits, $backend) };
        }
    }
    return \%cases;
}

sub measure {
    my ($cases, $seconds) = @_;
    my %results;
    for my $operation (sort keys %{$cases}) {
        for my $backend (qw(perl pdl)) {
            my $run = $cases->{$operation}{$backend};
            $run->();
            my $start = time;
            my $count = 0;
            do { $run->(); ++$count } while time - $start < $seconds;
            my $elapsed = time - $start;
            $results{$operation}{$backend} = {
                iterations       => $count,
                elapsed_seconds  => $elapsed,
                calls_per_second => $count / $elapsed
            };
        }
        my $pure = $results{$operation}{perl}{calls_per_second};
        my $fast = $results{$operation}{pdl}{calls_per_second};
        $results{$operation}{speedup} = $fast / $pure;
        printf "%s: Perl %.3f/s; PDL %.3f/s; ratio %.3fx\n", $operation, $pure, $fast,
            $fast / $pure;
    }
    return \%results;
}

my ($seconds, $output) = (1, undef);
GetOptions('seconds=f' => \$seconds, 'json=s' => \$output)
    or croak "Usage: perl maint/benchmark.pl [--seconds N] [--json FILE]\n";
croak "seconds must be between 0.1 and 60\n" if $seconds < 0.1 || $seconds > 60;
my $rate    = 8000;
my $events  = Ham::RTTY->new->events('CQ CQ DE TESTCALL');
my $samples = Ham::RTTY::Generator->new(sample_rate => $rate)->generate($events);
print "Platform: $^O / $Config{archname}; Perl $^V; PDL $PDL::VERSION\n";
print "8000 Hz, mono; wall-clock calls/second (higher is better).\n";
my $results = measure(cases($events, $samples, $rate), $seconds);

if (defined $output) {
    my $json = JSON::PP->new->canonical->pretty->encode(
        {
            platform          => $^O,
            architecture      => $Config{archname},
            perl              => "$^V",
            pdl               => "$PDL::VERSION",
            sample_rate       => $rate,
            pcm_samples       => $rate,
            detection_samples => scalar @{$samples},
            seconds_per_case  => $seconds,
            results           => $results
        }
    );
    open my $fh, '>:raw', $output or croak $!;
    print {$fh} $json or croak $!;
    close $fh         or croak $!;
}
1;
