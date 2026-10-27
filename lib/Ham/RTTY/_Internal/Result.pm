package Ham::RTTY::_Internal::Result;
use 5.020;
use strict;
use warnings;
use Hash::Util qw(lock_hash);

# Internal callers transfer validated payloads and do not mutate them afterward.
# Public construction still validates and deep-copies all caller-owned data.
sub from_owned {
    my ($factory, $class, %args) = @_;
    my $self = bless {
        text        => '',
        morse       => '',
        events      => {unit => 'us', segments => []},
        frequency   => undef,
        wpm         => undef,
        warnings    => [],
        complete    => 0,
        diagnostics => {},
        %args
    }, $class;
    lock_hash(%{$self});
    return $self;
}
1;
