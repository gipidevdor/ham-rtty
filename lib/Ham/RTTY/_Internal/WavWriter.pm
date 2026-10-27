package Ham::RTTY::_Internal::WavWriter;
use 5.020;
use strict;
use warnings;
use Ham::RTTY::_Internal::IO       qw(write_bytes);
use Carp                           qw(croak);
use Ham::RTTY::_Internal::Validate qw(fail samples);
sub state { my ($self) = @_; return $self->{state} }    ## no critic (Subroutines::ProhibitBuiltinHomonyms)

sub _quantize {
    my ($sample, $scale) = @_;
    my $value = $sample * $scale;
    $value = int($value >= 0 ? $value + 0.5 : $value - 0.5);
    return $value >= $scale ? $scale - 1 : $value;
}

sub feed {
    my ($self, $values) = @_;
    fail('RTTY_E_STATE', 'WAV writer is finalized or failed')
        if $self->{state} =~ /FINISHED|FAILED/x;
    samples($values, 1000000);
    fail('RTTY_E_ARGUMENT', 'More samples than declared')
        if $self->{written} + @{$values} > $self->{count};
    my $scale = 2**($self->{bits} - 1);
    my @ints =
        $self->{backend} eq 'pdl'
        ? Ham::RTTY::_Internal::PDL::quantize($values, $scale)
        : map { _quantize($_, $scale) } @{$values};
    my $raw;
    if ($self->{bits} == 8) {
        $raw = pack('C*', map { $_ + 128 } @ints);
    }
    elsif ($self->{bits} == 16) { $raw = pack('s<*', @ints) }
    else {
        $raw = join '', map { substr(pack('V', $_ < 0 ? $_ + 16777216 : $_), 0, 3) } @ints;
    }
    eval { write_bytes($self->{fh}, $raw); 1 } or do { $self->{state} = 'FAILED'; croak $@ };
    $self->{written} += @{$values};
    $self->{state} = 'ACTIVE';
    return $self;
}
sub result { my ($self) = @_; return {state => $self->{state}, samples => $self->{written}} }

sub finish {
    my ($self) = @_;
    fail('RTTY_E_STATE', 'WAV writer failed') if $self->{state} eq 'FAILED';
    return $self->result                      if $self->{state} eq 'FINISHED';
    fail('RTTY_E_ARGUMENT', 'Fewer samples than declared')
        unless $self->{written} == $self->{count};
    eval { write_bytes($self->{fh}, "\0") if $self->{bytes} % 2; 1 }
        or do { $self->{state} = 'FAILED'; croak $@ };
    $self->{state} = 'FINISHED';
    return $self->result;
}
1;
