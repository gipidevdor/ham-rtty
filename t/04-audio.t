use strict;
use warnings;
use Test::More;
use Ham::RTTY::Audio;

sub read_bytes {
    my ($bytes, %args) = @_;
    open my $fh, '<', \$bytes or die $!;
    return Ham::RTTY::Audio->new(%args)->read($fh);
}

sub wave {
    my ($fmt, $data, $extra) = @_;
    $extra //= '';
    my $body = 'WAVE'
        . pack('a4V', 'fmt ', length $fmt)
        . $fmt
        . $extra
        . pack('a4V', 'data', length $data)
        . $data;
    $body .= "\0" if length($data) % 2;
    return 'RIFF' . pack('V', length $body) . $body;
}
my @values = (-1, -0.5, 0, 0.5, 1);
for my $bits (8, 16, 24) {
    my $bytes = '';
    open my $fh, '>', \$bytes or die $!;
    my $stats = Ham::RTTY::Audio->new->write($fh, \@values, bits => $bits, sample_rate => 11025);
    close $fh;
    is($stats->{state}, 'FINISHED', 'writer finalized');
    my $result = read_bytes($bytes);
    is($result->{bits},        $bits, "read $bits bits");
    is($result->{sample_rate}, 11025, 'rate');
    my $step = 1 / 2**($bits - 1);

    for my $i (0 .. $#values) {
        cmp_ok(abs($result->{samples}[$i] - $values[$i]), '<=', $step, 'quantization bound');
    }
    is(unpack('V', substr($bytes, 4,  4)), length($bytes) - 8, 'RIFF size includes odd padding');
    is(unpack('V', substr($bytes, 40, 4)), 5 * $bits / 8,      'data size excludes padding');
}

# Construct stereo PCM independently of the writer.
my $fmt = pack('vvVVvv', 1, 2, 8000, 32000, 4, 16);
my $stereo =
    wave($fmt, pack('s<*', 32767, -32768, 8192, 16384), pack('a4V', 'JUNK', 3) . 'abc' . "\0");
is_deeply(read_bytes($stereo, stereo => 'left')->{samples},  [32767 / 32768, 0.25], 'left channel');
is_deeply(read_bytes($stereo, stereo => 'right')->{samples}, [-1, 0.5], 'right channel');
is_deeply(read_bytes($stereo, stereo => 'mix')->{samples},   [-1 / 65536, 0.375], 'mix channel');
for my $bits (8, 24) {
    my $frame = $bits == 8 ? pack('CC', 0, 255) : pack('C*', 0, 0, 128, 255, 255, 127);
    my $s = wave(pack('vvVVvv', 1, 2, 8000, 8000 * 2 * $bits / 8, 2 * $bits / 8, $bits), $frame);
    is_deeply(read_bytes($s, stereo => 'left')->{samples}, [-1],
        "stereo $bits negative full scale");
    cmp_ok(read_bytes($s, stereo => 'right')->{samples}[0],
        '>', 0.99, "stereo $bits positive full scale");
}
my $mono = wave(pack('vvVVvv', 1, 1, 8000, 16000, 2, 16), pack('s<*', -32768, 0, 32767));
for my $length (0 .. length($mono) - 1) {
    eval { read_bytes(substr($mono, 0, $length)) };
    isa_ok($@, 'Ham::RTTY::Error', "truncation at $length");
}
my @mutations = (
    [0,  'RIFX', 'RTTY_E_WAV_FORMAT'],
    [8,  'xxxx', 'RTTY_E_WAV_FORMAT'],
    [20, pack('v', 3),       'RTTY_E_WAV_FORMAT'],
    [22, pack('v', 3),       'RTTY_E_WAV_FORMAT'],
    [28, pack('V', 3),       'RTTY_E_WAV_FORMAT'],
    [32, pack('v', 1),       'RTTY_E_WAV_FORMAT'],
    [34, pack('v', 32),      'RTTY_E_WAV_FORMAT'],
    [40, pack('V', 1000000), 'RTTY_E_WAV_TRUNCATED']
);
for my $m (@mutations) {
    my $bad = $mono;
    substr($bad, $m->[0], length $m->[1], $m->[1]);
    eval { read_bytes($bad) };
    is((ref($@) ? $@->code : "$@"), $m->[2], 'malformed header');
}
eval { read_bytes($mono, max_bytes => 44) };
is((ref($@) ? $@->code : "$@"), 'RTTY_E_RESOURCE', 'input byte limit');
my $empty = '';
open my $out, '>', \$empty or die $!;
my $writer = Ham::RTTY::Audio->new->writer($out, sample_count => 2, bits => 16);
eval { $writer->feed([0, 2]) };
is((ref($@) ? $@->code : "$@"), 'RTTY_E_ARGUMENT', 'reject invalid block');
is($writer->state,              'READY',           'invalid block is atomic');
eval { $writer->finish };
is((ref($@) ? $@->code : "$@"), 'RTTY_E_ARGUMENT', 'reject premature finish');
$writer->feed([0, 0]);
is($writer->finish->{samples}, 2, 'recover after validation');
is($writer->finish->{samples}, 2, 'idempotent finish');
eval { $writer->feed([]) };
is((ref($@) ? $@->code : "$@"), 'RTTY_E_STATE', 'reject post-finish feed');
my $bytes = '';
open my $zero, '>', \$bytes or die $!;
Ham::RTTY::Audio->new->write($zero, [], bits => 24);
close $zero;
is_deeply(read_bytes($bytes)->{samples}, [], 'empty WAV');
done_testing;
