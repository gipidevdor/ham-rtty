package CorpusMetrics;
use strict;
use warnings;
use Exporter 'import';
our @EXPORT_OK = qw(character_error_rate);

sub character_error_rate {
    my ($reference, $actual) = @_;
    die 'A nonempty reference is required' unless defined($reference) && length($reference);
    my @previous = 0 .. length($actual);
    for my $i (1 .. length($reference)) {
        my @row = ($i);
        for my $j (1 .. length($actual)) {
            my @cost = (
                $previous[$j] + 1,
                $row[$j - 1] + 1,
                $previous[$j - 1] + (substr($reference, $i - 1, 1) ne substr($actual, $j - 1, 1))
            );
            my $best = $cost[0];
            for my $cost (@cost) { $best = $cost if $cost < $best }
            push @row, $best;
        }
        @previous = @row;
    }
    return $previous[-1] / length($reference);
}
1;
