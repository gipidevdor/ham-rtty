package Ham::RTTY::_Internal::Biquad;
use 5.020;
use strict;
use warnings;
my $PI = 4 * atan2(1, 1);

# Original implementation of the RBJ constant-peak band-pass equations.
# alpha = tan(pi * bandwidth / rate) specifies the digital full -3 dB
# width of one section. The cascade is narrower and has unity centre gain.
# Coefficient reference: https://www.w3.org/TR/audio-eq-cookbook/#bpf-0db
sub new {
    my ($class, $rate, $frequency, $bandwidth) = @_;
    my $omega = 2 * $PI * $frequency / $rate;
    my $angle = $PI * $bandwidth / $rate;
    my $alpha = sin($angle) / cos($angle);
    my $a0    = 1 + $alpha;
    return bless {
        gain  => $alpha / $a0,
        a1    => -2 * cos($omega) / $a0,
        a2    => (1 - $alpha) / $a0,
        delay => 2 / $alpha,
        state => [[0, 0], [0, 0]]
    }, $class;
}

sub delay_samples { my ($self) = @_; return $self->{delay} }

sub process {
    my ($self, $block)          = @_;
    my ($gain, $a1, $a2)        = @{$self}{qw(gain a1 a2)};
    my ($stage_one, $stage_two) = @{$self->{state}};
    my ($p1, $p2)               = @{$stage_one};
    my ($q1, $q2)               = @{$stage_two};
    my @out;

    # Both sections advance per sample; each output depends only on the
    # section's own state, so this equals filtering the block twice.
    for my $input (@{$block}) {
        my $middle = $gain * $input + $p1;
        $p1 = -$a1 * $middle + $p2;
        $p2 = -$gain * $input - $a2 * $middle;
        my $output = $gain * $middle + $q1;
        $q1 = -$a1 * $output + $q2;
        $q2 = -$gain * $middle - $a2 * $output;
        push @out, $output;
    }
    @{$stage_one} = ($p1, $p2);
    @{$stage_two} = ($q1, $q2);
    return \@out;
}
1;
