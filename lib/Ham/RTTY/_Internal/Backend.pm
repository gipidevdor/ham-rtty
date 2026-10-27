package Ham::RTTY::_Internal::Backend;
use 5.020;
use strict;
use warnings;
use Ham::RTTY::_Internal::Validate qw(fail);

sub resolve {
    my ($backend) = @_;
    $backend //= 'perl';
    fail('RTTY_E_ARGUMENT', 'backend must be perl, pdl or auto')
        if ref($backend) || $backend !~ /\A(?:perl|pdl|auto)\z/x;
    return 'perl' if $backend eq 'perl';

    # Perl 5.20 may accept an undef %INC entry left by a failed require.
    my $available =
        eval { require Ham::RTTY::_Internal::PDL; defined $INC{'Ham/RTTY/_Internal/PDL.pm'} };
    return 'pdl'  if $available;
    return 'perl' if $backend eq 'auto';
    fail('RTTY_E_ARGUMENT', 'PDL backend unavailable; install PDL 2.081 or later');
    return;
}
1;
