use strict;
use warnings;
use Test::More;
for my $module (
    qw(Ham::RTTY Ham::RTTY::Encoder Ham::RTTY::Decoder Ham::RTTY::Events
    Ham::RTTY::Generator Ham::RTTY::Detector Ham::RTTY::MIDI Ham::RTTY::Audio Ham::RTTY::Result Ham::RTTY::Error)
    )
{
    use_ok($module);
}
done_testing;
