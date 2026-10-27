use strict;
use warnings;
use Test::More;
use Symbol qw(gensym);
use lib 't/lib';
use FaultHandle;
use Ham::RTTY::Audio;
use Ham::RTTY::MIDI;
my $wave = '';
open my $out, '>', \$wave or die $!;
Ham::RTTY::Audio->new->write($out, [0, 0.5, -0.5]);
close $out;

sub handle {
    my (%args) = @_;
    my $fh = gensym();
    tie *{$fh}, 'FaultHandle', %args;
    return $fh;
}
for my $fault ({binmode => 1}, {seek => 1}, {seek => 2}, {seek => 3}, {seek => 5}, {read => 1}) {
    my $fh = handle(bytes => $wave, fail => $fault);
    eval { Ham::RTTY::Audio->new->reader($fh) };
    is((ref($@) ? $@->code : "$@"), 'RTTY_E_IO', 'structured failure for reader operation');
}
my $partial = handle(bytes => $wave, max_read => 1);
is_deeply(Ham::RTTY::Audio->new->read($partial)->{samples}, [0, 0.5, -0.5],
    'short reads are retried');
my $read_fail = handle(bytes => $wave, fail => {read => 5});
my $reader    = Ham::RTTY::Audio->new->reader($read_fail);
eval { $reader->{next}->() };
is((ref($@) ? $@->code : "$@"), 'RTTY_E_IO', 'read failure during iteration');
for my $fault ({binmode => 1}, {print => 1}) {
    my $fh = handle(fail => $fault);
    eval { Ham::RTTY::Audio->new->writer($fh, sample_count => 1) };
    is((ref($@) ? $@->code : "$@"), 'RTTY_E_IO', 'structured output initialization failure');
}
my $broken = handle(fail => {print => 2});
my $writer = Ham::RTTY::Audio->new->writer($broken, sample_count => 1);
eval { $writer->feed([0]) };
is((ref($@) ? $@->code : "$@"), 'RTTY_E_IO', 'PCM write failure');
is($writer->state,              'FAILED',  'irreversible write failure state');
eval { $writer->feed([]) };
is((ref($@) ? $@->code : "$@"), 'RTTY_E_STATE', 'cannot feed failed writer');
eval { $writer->finish };
is((ref($@) ? $@->code : "$@"), 'RTTY_E_STATE', 'cannot finalize failed writer');
my $padding = handle(fail => {print => 3});
my $odd     = Ham::RTTY::Audio->new->writer($padding, sample_count => 1, bits => 8);
$odd->feed([0]);
eval { $odd->finish };
is((ref($@) ? $@->code : "$@"), 'RTTY_E_IO', 'padding failure');
is($odd->state,                 'FAILED',  'padding failure state');
my $midi = handle(fail => {binmode => 1});
eval { Ham::RTTY::MIDI->new->write($midi, {unit => 'us', segments => []}) };
is((ref($@) ? $@->code : "$@"), 'RTTY_E_IO', 'MIDI binary-mode failure');
done_testing;
