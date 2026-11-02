package Ham::RTTY::_Internal::Data;
use 5.020;
use strict;
use warnings;
use Exporter 'import';
use Scalar::Util qw(blessed refaddr);
our @EXPORT_OK = qw(plain_data);

# Memoized subtree heights preserve shared children without revisiting every path.
sub plain_data {
    my ($value) = @_;
    my @pending = ([$value, 0, 0]);
    my (%active, %height);
    while (my $item = pop @pending) {
        my ($node, $depth, $leaving) = @{$item};
        next unless ref $node;
        my $address = refaddr($node);
        if ($leaving) {
            my $maximum = 0;
            for my $child (ref($node) eq 'ARRAY' ? @{$node} : values %{$node}) {
                next unless ref $child;
                my $distance = 1 + $height{refaddr($child)};
                $maximum = $distance if $distance > $maximum;
            }
            $height{$address} = $maximum;
            delete $active{$address};
            next;
        }
        return 0 if blessed($node) || $depth > 64 || $active{$address};
        if (exists $height{$address}) {
            return 0 if $depth + $height{$address} > 64;
            next;
        }
        my $kind = ref $node;
        return 0 unless $kind eq 'ARRAY' || $kind eq 'HASH';
        $active{$address} = 1;
        push @pending, [$node, $depth, 1];
        push @pending, map { [$_, $depth + 1, 0] } $kind eq 'ARRAY' ? @{$node} : values %{$node};
    }
    return 1;
}
1;
