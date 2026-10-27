package Reference;
use strict;
use warnings;
use Exporter 'import';
our @EXPORT_OK = qw(reference_sos noise);

# Fixed SOS schedule: deliberately does not use any Ham::RTTY encoder/generator.
sub reference_sos {
    my (%args)    = @_;
    my $rate      = $args{rate} // 8000;
    my $unit      = $rate * 1.2 / ($args{wpm} // 20);
    my $frequency = $args{frequency} // 650;
    my $amplitude = $args{amplitude} // 0.6;
    my @runs      = (
        [0, 3], [1, 1], [0, 1], [1, 1], [0, 1], [1, 1], [0, 3], [1, 3], [0, 1], [1, 3],
        [0, 1], [1, 3], [0, 3], [1, 1], [0, 1], [1, 1], [0, 1], [1, 1], [0, 3]
    );
    my (@out, $time, $phase);
    ($time, $phase) = (0, 0);
    my $pi = 4 * atan2(1, 1);

    for my $run (@runs) {
        my $n = int($run->[1] * $unit + 0.5);
        for (1 .. $n) {
            my $frequency_now = $frequency + ($args{drift} // 0) * sin(2 * $pi * $time / $rate);
            my $gain = $args{fading} ? 0.7 + 0.3 * sin(2 * $pi * $time / ($rate * 0.7)) : 1;
            push @out, $run->[0] * $amplitude * $gain * sin($phase);

            # Integrate frequency through both marks and gaps.
            $phase += 2 * $pi * $frequency_now / $rate;
            $phase -= 2 * $pi if $phase >= 2 * $pi;
            ++$time;
        }
    }
    return \@out;
}

sub noise {
    my ($count, $amplitude) = @_;
    my $seed = 1234567;
    return [
        map {
            $seed = (1664525 * $seed + 1013904223) % 4294967296;
            ($seed / 4294967296 * 2 - 1) * $amplitude
        } 1 .. $count
    ];
}
1;
