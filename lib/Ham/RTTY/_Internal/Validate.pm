package Ham::RTTY::_Internal::Validate;
use 5.020;
use strict;
use warnings;
use Exporter 'import';
use Scalar::Util qw(looks_like_number);
use Ham::RTTY::Error;
our @EXPORT_OK = qw(fail number integer options samples named_arguments);

sub fail {
    my ($code, $message) = @_;
    return Ham::RTTY::Error->throw(code => $code, message => $message);
}

sub named_arguments {
    my (@pairs) = @_;
    fail('RTTY_E_ARGUMENT', 'Options must be name/value pairs') if @pairs % 2;
    my %args;
    for (my $i = 0; $i < @pairs; $i += 2) {
        my $name = $pairs[$i];
        fail('RTTY_E_ARGUMENT', 'Option names must be defined scalars')
            if !defined($name) || ref($name);
        fail('RTTY_E_ARGUMENT', 'Duplicate option name') if exists $args{$name};
        $args{$name} = $pairs[$i + 1];
    }
    return %args;
}

sub number {
    my ($name, $value, $min, $max) = @_;
    fail('RTTY_E_ARGUMENT', "$name must be a finite number in [$min, $max]")
        if !defined($value)
        || ref($value)
        || !looks_like_number($value)
        || "$value" =~ /nan|inf/ix
        || $value < $min
        || $value > $max;
    return 0 + $value;
}

sub integer {
    my ($name, $value, $min, $max) = @_;
    number($name, $value, $min, $max);
    fail('RTTY_E_ARGUMENT', "$name must be an integer") if int($value) != $value;
    return 0 + $value;
}

sub options {
    my ($args, @names) = @_;
    my %known = map { $_ => 1 } @names;
    for my $key (keys %{$args}) {
        fail('RTTY_E_ARGUMENT', "Unknown option: $key") unless $known{$key};
    }
    return;
}

sub samples {
    my ($values, $limit) = @_;
    fail('RTTY_E_ARGUMENT', 'Samples must be an array reference') unless ref($values) eq 'ARRAY';
    fail('RTTY_E_RESOURCE', 'Sample block exceeds limit') if @{$values} > $limit;
    for my $sample (@{$values}) {
        fail('RTTY_E_ARGUMENT', 'sample must be a finite number in [-1, 1]')
            if !defined($sample)
            || ref($sample)
            || !looks_like_number($sample)
            || !($sample >= -1 && $sample <= 1);
    }
    return;
}
1;
