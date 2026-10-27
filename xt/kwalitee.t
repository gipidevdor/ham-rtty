use strict;
use warnings;
use Test::More;
use Test::Kwalitee qw(kwalitee_ok);
use Ham::RTTY        ();
if (!-f 'META.yml') {
    chdir "Ham-RTTY-$Ham::RTTY::VERSION" or die "Run make distmeta before author checks: $!";
}
kwalitee_ok();
done_testing;
