#!/usr/bin/env perl
use 5.020;
use strict;
use warnings;
use lib 'lib';
use Carp         qw(croak);
use Getopt::Long qw(GetOptions Configure);
use JSON::PP;
use Ham::RTTY;
use Ham::RTTY::Events qw(to_samples);
Configure(qw(no_auto_abbrev no_ignore_case));
my $backend = 'perl';
my %reception;
my (%modes, $help);
GetOptions(
    'create=s'  => \$modes{create},
    'read=s'    => \$modes{read},
    'stream'    => \$modes{stream},
    'collect'   => \$modes{collect},
    'baseline'  => \$modes{baseline},
    'backend=s' => \$backend,
    'baud=f'    => \$reception{baud},
    'mark=f'    => \$reception{mark},
    'shift=f'   => \$reception{shift},
    'help'      => \$help
) or croak 'Use --help for options';

if ($help) {
    print "Usage: perl maint/memory.pl --create FILE.wav [--backend perl|pdl]\n",
        "       perl maint/memory.pl --read FILE.wav [--backend perl|pdl]\n",
        "         [--baud 45.45 --mark 2125 --shift 170]\n",
        "       perl maint/memory.pl --baseline|--stream|--collect [--backend perl|pdl]\n",
        "Generation uses exactly 120 seconds at 48000 Hz, in 4096-sample blocks.\n",
        "Measure each invocation in a fresh process; create fixtures separately.\n";
    exit 0;
}
my @selected = grep { defined $modes{$_} } keys %modes;
croak 'Select exactly one workload; use --help' if @selected != 1 || @ARGV;
croak 'backend must be perl or pdl for an explicit comparison'
    unless $backend =~ /\A(?:perl|pdl)\z/x;
my ($mode)   = @selected;
my $path     = $modes{$mode};
my %received = map { defined($reception{$_}) ? ($_ => $reception{$_}) : () } keys %reception;
croak 'baud, mark and shift apply only to --read' if $mode ne 'read' && keys %received;
my $rate   = 48000;
my $rtty   = Ham::RTTY->new(sample_rate => $rate, backend => $backend);
my %report = (mode => $mode, backend => $backend, block_samples => 4096);

if ($mode eq 'read') {
    my %receiver = (baud => 45.45, mark => 2125, shift => 170, %received);
    my $result   = $rtty->read_wav($path, %receiver);
    $report{reception} = \%receiver;
    %report = (
        %report,
        text            => $result->text,
        text_characters => length($result->text),
        complete        => $result->complete,
        diagnostics     => $result->diagnostics,
        warnings        => $result->warnings
    );
}
elsif ($mode ne 'baseline') {
    my $measurements = generation_workload($mode, $path, $rtty, $rate);
    %report = (%report, %{$measurements});
}
$report{pdl_loaded}  = exists($INC{'PDL.pm'}) ? JSON::PP::true : JSON::PP::false;
$report{pdl_version} = PDL->VERSION if exists $INC{'PDL.pm'};
print JSON::PP->new->utf8->canonical->pretty->encode(\%report);

sub fixed_events {
    my ($facade, $sample_rate) = @_;
    my $events = to_samples($facade->events(join ' ', ('CQ TEST 123 73') x 100), $sample_rate);
    my @runs;
    my $remaining = 120 * $sample_rate;
    for my $run (@{$events->{segments}}) {
        last unless $remaining;
        my $count = $run->{samples} < $remaining ? $run->{samples} : $remaining;
        push @runs, {state => $run->{state}, samples => $count};
        $remaining -= $count;
    }
    croak 'Not enough source audio' if $remaining;
    return {sample_rate => $sample_rate, segments => \@runs};
}

sub generation_workload {
    my ($operation, $filename, $facade, $sample_rate) = @_;
    my %statistics;
    my $events    = fixed_events($facade, $sample_rate);
    my $generator = $facade->generator;
    if ($operation eq 'collect') {
        my $samples = $generator->generate($events);
        $statistics{sample_count} = scalar @{$samples};
    }
    else {
        my $next = $generator->stream($events, 4096);
        if ($operation eq 'create') {
            open my $out, '>:raw', $filename or croak $!;
            my $writer = Ham::RTTY::Audio->new(backend => $backend)->writer(
                $out,
                sample_rate  => $sample_rate,
                sample_count => 120 * $sample_rate,
                bits         => 16
            );
            while (my $block = $next->()) { $writer->feed($block) }
            $writer->finish;
            close $out or croak $!;
        }
        else {
            my $count = 0;
            while (my $block = $next->()) { $count += @{$block} }
            $statistics{sample_count} = $count;
        }
    }
    $statistics{generation} = $generator->result;
    croak 'Generation did not consume the complete workload'
        unless $statistics{generation}{samples} == 120 * $sample_rate
        && $statistics{generation}{state} eq 'FINISHED';
    return \%statistics;
}
