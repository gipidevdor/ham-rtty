#!/usr/bin/env perl
use 5.020;
use strict;
use warnings;
use lib 'lib';
use Carp qw(croak);
use JSON::PP;
use Ham::RTTY;
use Ham::RTTY::Events qw(to_samples);
my ($mode, $path) = @ARGV;
croak 'Usage: memory.pl --create|--read FILE.wav'
    unless @ARGV == 2 && $mode =~ /\A--(?:create|read)\z/x;
my $rate = 48000;
my $rtty = Ham::RTTY->new(sample_rate => $rate);

if ($mode eq '--create') {
    my $events = to_samples($rtty->events(join ' ', ('CQ TEST 123 73') x 100), $rate);
    my (@runs, $remaining);
    $remaining = 120 * $rate;
    for my $run (@{$events->{segments}}) {
        last unless $remaining;
        my $count = $run->{samples} < $remaining ? $run->{samples} : $remaining;
        push @runs, {state => $run->{state}, samples => $count};
        $remaining -= $count;
    }
    croak 'Not enough source audio' if $remaining;
    my $next = $rtty->generator->stream({sample_rate => $rate, segments => \@runs}, 4096);
    open my $out, '>:raw', $path or croak $!;
    my $writer = Ham::RTTY::Audio->new->writer(
        $out,
        sample_rate  => $rate,
        sample_count => 120 * $rate,
        bits         => 16
    );
    while (my $block = $next->()) { $writer->feed($block) }
    $writer->finish;
    close $out or croak $!;
    print "Created 120 seconds at 48000 Hz, 16-bit mono: $path\n";
}
else {
    my $result = $rtty->read_wav($path, baud => 45.45);
    print JSON::PP->new->canonical->pretty->encode(
        {
            text_characters => length($result->text),
            complete        => $result->complete,
            diagnostics     => $result->diagnostics,
            warnings        => $result->warnings
        }
    );
}
