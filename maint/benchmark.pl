#!/usr/bin/env perl
use 5.020;
use strict;
use warnings;
use lib 'lib';
use Carp         qw(croak);
use Getopt::Long qw(GetOptions);
use JSON::PP;
use Time::HiRes qw(time);
use Ham::RTTY;
use Ham::RTTY::Generator;
use Ham::RTTY::Detector;
use Ham::RTTY::_Internal::Validate qw(integer);

my ($rate, $block_size, $repeat, $iterations, $snapshots) = (8000, 4096, 1, 3, 100);
my ($known, $json, $help);
GetOptions(
    'rate=i'           => \$rate,
    'block=i'          => \$block_size,
    'repeat=i'         => \$repeat,
    'iterations=i'     => \$iterations,
    'snapshots=i'      => \$snapshots,
    'known-frequency!' => \$known,
    'json!'            => \$json,
    'help'             => \$help
) or die "Invalid benchmark options\n";

if ($help) {
    print "Usage: perl maint/benchmark.pl [--rate 8000] [--block 4096] [--repeat 1]\n",
        "  [--iterations 3] [--snapshots 100] [--known-frequency] [--json]\n";
    exit 0;
}
die "Unexpected arguments\n" if @ARGV;
integer('rate',       $rate,       1000, 384000);
integer('block',      $block_size, 1,    1000000);
integer('repeat',     $repeat,     1,    100);
integer('iterations', $iterations, 1,    10000);
integer('snapshots',  $snapshots,  1,    1000000);
my $frequency = 2125;
my $rtty      = Ham::RTTY->new(sample_rate => $rate, mark => $frequency);
my $text      = join ' ', ('CQ CQ DE TESTCALL') x $repeat;
my $events    = $rtty->events($text);
my $samples =
    Ham::RTTY::Generator->new(sample_rate => $rate, mark => $frequency)->generate($events);
my $wav = '';
open my $out, '>:raw', \$wav or croak $!;
$rtty->generate_wav($text, $out);
close $out or croak $!;
my @backends      = ('perl');
my $pdl_available = eval { require Ham::RTTY::_Internal::PDL; 1 };
push @backends, 'pdl' if $pdl_available;
my @results;

for my $backend (@backends) {
    my %detector_options = (sample_rate => $rate, backend => $backend, search => $known ? 0 : 1);
    $detector_options{mark} = $frequency if $known;
    my $ready = Ham::RTTY::Detector->new(%detector_options);
    my $feed  = sub { feed_blocks($_[0], $samples, $block_size); };
    $feed->($ready);
    $ready->result;
    my %cases = (
        generate => sub {
            Ham::RTTY::Generator->new(
                sample_rate => $rate,
                mark        => $frequency,
                backend     => $backend
            )->generate($events);
        },
        detect => sub {
            my $detector = Ham::RTTY::Detector->new(%detector_options);
            $feed->($detector);
            $detector->finish;
        },
        wav_generate => sub {
            open my $handle, '>:raw', \my $bytes or croak $!;
            Ham::RTTY->new(sample_rate => $rate, mark => $frequency, backend => $backend)
                ->generate_wav($text, $handle);
            close $handle or croak $!;
        },
        wav_decode => sub {
            open my $handle, '<:raw', \$wav or croak $!;
            Ham::RTTY->new(backend => $backend)
                ->decode_wav($handle, $known ? (mark => $frequency) : (search => 1));
            close $handle or croak $!;
        },
        snapshot_rebuild => sub { $ready->_snapshot(0); },
        snapshots        => sub { $ready->result for 1 .. $snapshots; },
    );
    for my $operation (sort keys %cases) {
        my ($user_before, $system_before) = times;
        my $start = time;
        $cases{$operation}->() for 1 .. $iterations;
        my $elapsed = time - $start;
        my ($user_after, $system_after) = times;
        my $cpu = $user_after + $system_after - $user_before - $system_before;
        push @results,
            {
            backend              => $backend,
            operation            => $operation,
            iterations           => $iterations,
            cpu_seconds          => $cpu,
            wall_seconds         => $elapsed,
            cpu_seconds_per_call => $cpu / $iterations,
            };
    }
}
my $report = {
    perl               => "$^V",
    pdl_available      => $pdl_available ? 1 : 0,
    sample_rate        => $rate,
    block_samples      => $block_size,
    sample_count       => scalar @{$samples},
    audio_seconds      => @{$samples} / $rate,
    known_frequency    => $known ? 1 : 0,
    snapshots_per_call => $snapshots,
    results            => \@results,
};
print_report($report, $json);

sub print_report {
    my ($data, $as_json) = @_;
    if ($as_json) { print JSON::PP->new->canonical->pretty->encode($data); }
    else {
        printf "Perl %s; %d Hz; %.2f seconds audio; %d sample blocks; %s tone\n",
            $data->{perl}, $data->{sample_rate}, $data->{audio_seconds},
            $data->{block_samples}, $data->{known_frequency} ? 'known' : 'searched';
        print "PDL unavailable: measuring Perl only\n" unless $data->{pdl_available};
        for my $row (@{$data->{results}}) {
            printf "%-5s %-17s %.6f CPU seconds/call (%d iterations)\n",
                @{$row}{qw(backend operation cpu_seconds_per_call iterations)};
        }
        print "Snapshot calls contain $data->{snapshots_per_call} cached reads; ",
            "very short timings may round to zero.\n";
    }
    return;
}

sub feed_blocks {
    my ($detector, $input_samples, $size) = @_;
    for (my $offset = 0; $offset < @{$input_samples}; $offset += $size) {
        my $end = $offset + $size - 1;
        $end = $#{$input_samples} if $end > $#{$input_samples};
        $detector->feed([@{$input_samples}[$offset .. $end]]);
    }
    return;
}

1;
