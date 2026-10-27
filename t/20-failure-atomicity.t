use strict;
use warnings FATAL => 'all';
our ($fail_open, $fail_close, $fail_rename, $fail_chmod);

BEGIN {
    *CORE::GLOBAL::open = sub (*;$@) {
        return 0 if $main::fail_open;
        return @_ == 2 ? CORE::open($_[0], $_[1]) : CORE::open($_[0], $_[1], $_[2]);
    };
    *CORE::GLOBAL::close = sub (*) {
        my $closed = CORE::close($_[0]);
        return $main::fail_close ? 0 : $closed;
    };
    *CORE::GLOBAL::rename = sub ($$) {
        return 0 if $main::fail_rename;
        return CORE::rename($_[0], $_[1]);
    };
    *CORE::GLOBAL::chmod = sub {
        return 0 if $main::fail_chmod;
        return CORE::chmod($_[0], $_[1]);
    };
}
use Test::More;
use File::Temp qw(tempdir);
use Ham::RTTY;
use Ham::RTTY::_Internal::IO qw(with_file);
my $rtty = Ham::RTTY->new;
for my $method (qw(wav_bytes decode_wav_bytes)) {
    my $input = $method eq 'wav_bytes' ? 'A' : $rtty->wav_bytes('A');
    {
        local $fail_open = 1;
        eval { $rtty->$method($input) };
        is(ref($@) ? $@->code : '', 'RTTY_E_IO', "$method open failure");
    }
    {
        local $fail_close = 1;
        eval { $rtty->$method($input) };
        is(ref($@) ? $@->code : '', 'RTTY_E_IO', "$method close failure");
    }
}
my $dir  = tempdir(CLEANUP => 1);
my $path = "$dir/destination.wav";
$rtty->write_wav('CQ', $path);
{
    local $fail_rename = 1;
    eval { $rtty->write_wav('TEST', $path, overwrite => 1) };
    is(ref($@) ? $@->code : '', 'RTTY_E_IO', 'rename failure is structured');
}
is($rtty->read_wav($path)->text, 'CQ', 'rename failure preserves old destination');
{
    local $fail_chmod = 1;
    eval { $rtty->write_wav('TEST', $path, overwrite => 1) };
    is(ref($@) ? $@->code : '', 'RTTY_E_IO', 'permission-setting failure is structured');
}
is($rtty->read_wav($path)->text, 'CQ', 'chmod failure preserves destination');
{
    local $fail_close = 1;
    eval { $rtty->write_wav('TEST', "$dir/failed.wav") };
    is(ref($@) ? $@->code : '', 'RTTY_E_IO', 'close failure is structured');
}
ok(!-e "$dir/failed.wav", 'close failure removes incomplete new file');
{
    no warnings 'redefine';
    local *Ham::RTTY::_Internal::IO::tempfile = sub { die 'injected temporary creation error' };
    eval { $rtty->write_wav('TEST', $path, overwrite => 1) };
    is(ref($@) ? $@->code : '', 'RTTY_E_IO', 'temporary creation failure');
}
is_deeply([glob "$dir/.ham-rtty-*"], [], 'all failure paths clean temporary siblings');
my $d = Ham::RTTY::Decoder->new;
is($d->state, 'READY', 'decoder lifecycle accessor');
is($d->decode_bits('0110111101011011')->text,
    "\x{fffd}", 'unassigned received figures retain replacement');
$d->reset->feed(
    {
        unit     => 'bits',
        baud     => 45.45,
        segments => [{state => 'space', duration => 7}, {state => 'mark', duration => 2}]
    }
);
is($d->finish->diagnostics->{framing_error_count}, 1, 'framing diagnostic');
is($d->finish->complete,                           1, 'repeated decoder finish');
done_testing;
