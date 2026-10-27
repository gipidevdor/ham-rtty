#!/usr/bin/env perl
use 5.020;
use strict;
use warnings;
use Carp qw(croak);
use Ham::RTTY;
use Ham::RTTY::Generator;

my $backend = shift @ARGV // 'perl';
my $rtty    = Ham::RTTY->new(baud => 50, sample_rate => 8000, mark => 650, backend => $backend);
my $configuration =
    Ham::RTTY::Generator->validate(sample_rate => 8000, mark => 650, backend => $backend);
my $generator = Ham::RTTY::Generator->new(%{$configuration});
my $timed     = $rtty->events('SOS');
my $sampled   = $rtty->sampled_events('SOS');
print 'Generator initial state: ', $generator->state, "\n";
my $collected   = $generator->generate($timed);
my $saved_first = $collected->[0];
$generator->reset;
my $next  = $generator->stream($sampled, 137);
my $count = 0;
while (my $block = $next->()) { $count += @{$block} }
croak 'Stream count differs'            unless $count == @{$collected};
croak 'Reset changed collected samples' unless $collected->[0] == $saved_first;
print "Backend: $configuration->{backend}; samples: $count; state: ", $generator->state, "\n";
print 'Progress count: ', $generator->result->{samples},                                 "\n";

# Factory generators and facade iterators each have independent ownership.
my $manual = $rtty->generator(amplitude => 0.3)->generate($sampled);
my $values = $rtty->samples('SOS');
my $a      = $rtty->stream_samples('SOS', block_size => 137);
my $b      = $rtty->stream_samples('SOS', block_size => 511);
my ($a_count, $b_count) = (0, 0);
while (1) {
    my $left_block  = $a->();
    my $right_block = $b->();
    last unless $left_block || $right_block;
    $a_count += @{$left_block}  if $left_block;
    $b_count += @{$right_block} if $right_block;
}
croak 'Independent stream counts differ' unless $a_count == @{$values} && $b_count == @{$manual};
my $empty = $rtty->stream_samples('');
croak 'Empty stream must reach EOF' if defined $empty->();
print "Independent streams: $a_count / $b_count\nExample completed: sample-streams\n";
