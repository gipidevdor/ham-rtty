package Ham::RTTY::_Internal::PDL;
use 5.020;
use strict;
use warnings;
use PDL 2.081 ();
use PDL::LiteF;
my $PI = 4 * atan2(1, 1);

sub fsk_tone {
    my ($phase, $step, $count, $amplitude, $offset) = @_;
    my $indices = PDL->sequence(PDL::double(), $count);
    return [((($indices + $offset) * $step + $phase)->sin * $amplitude)->list];
}

# One broadcast projects both tones; first dimension is time, second is tone.
sub powers {
    my ($values, $frequencies, $rate) = @_;
    my $n         = @{$values};
    my $index     = PDL->sequence(PDL::double(), $n)->dummy(1);
    my $frequency = PDL->pdl(PDL::double(), $frequencies)->dummy(0);
    my $phase     = $index * $frequency * (2 * $PI / $rate);
    my $data      = PDL->pdl(PDL::double(), $values)->dummy(1);
    my $real      = ($data * $phase->cos)->sumover;
    my $imag      = ($data * $phase->sin)->sumover;
    return [($real * $real + $imag * $imag)->list];
}

sub decode_pcm {
    my ($raw, $bits, $channels, $policy) = @_;
    my @integers;
    if    ($bits == 8)  { @integers = unpack('C*',  $raw) }
    elsif ($bits == 16) { @integers = unpack('s<*', $raw) }
    else {
        for (my $i = 0; $i < length $raw; $i += 3) {
            push @integers, unpack('V', substr($raw, $i, 3) . "\0");
        }
    }
    return [] unless @integers;
    my $values = PDL->pdl(PDL::double(), \@integers);
    if    ($bits == 8)  { $values -= 128 }
    elsif ($bits == 24) { $values -= ($values >= 8388608) * 16777216 }
    $values /= 2**($bits - 1);
    if ($channels == 2) {
        $values = $values->reshape(2, scalar(@integers) / 2);
        $values =
              $policy eq 'mix'
            ? $values->sumover / 2
            : $values->slice(($policy eq 'left' ? '0' : '1') . ',:')->flat;
    }
    return [$values->list];
}

sub quantize {
    my ($values, $scale) = @_;
    return () unless @{$values};
    my $scaled  = PDL->pdl(PDL::double(), $values) * $scale;
    my $rounded = ($scaled->abs + 0.5)->floor * (($scaled >= 0) * 2 - 1);
    return $rounded->clip(-$scale, $scale - 1)->list;
}
1;
