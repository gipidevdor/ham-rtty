use 5.020;
use strict;
use warnings FATAL => 'all';
use Test::More;
use File::Temp qw(tempdir);
use Ham::RTTY;
my $rtty = Ham::RTTY->new;
my $dir  = tempdir(CLEANUP => 1);
my $path = "$dir/message.wav";
$rtty->write_wav('CQ 123', $path);
is($rtty->read_wav($path)->text, 'CQ 123', 'file round trip');
ok(!eval { $rtty->write_wav('A', $path); 1 }, 'existing file protected');
$rtty->write_wav('TEST', $path, overwrite => 1);
is($rtty->read_wav($path)->text, 'TEST', 'explicit replacement');
ok(!eval { $rtty->write_wav('@', $path, overwrite => 1); 1 }, 'failed replacement');
is($rtty->read_wav($path)->text, 'TEST', 'old file preserved');

for my $bits (8, 16, 24) {
    is($rtty->decode_wav_bytes($rtty->wav_bytes('CQ 73', bits => $bits))->text,
        'CQ 73', "PCM depth $bits");
}
my $midi = $rtty->midi_bytes('CQ 123');
is(substr($midi, 0, 4),              'MThd', 'MIDI header');
is(unpack('n', substr($midi, 8, 2)), 0,      'MIDI type 0');
like($midi, qr/\x90\x4d\x64/, 'MARK note');
like($midi, qr/\x90\x4f\x64/, 'SPACE note');
$rtty->write_midi('TEST', "$dir/message.mid", mark_note => 60, space_note => 62);
ok(-s "$dir/message.mid", 'MIDI path');
my $next = $rtty->stream_samples('A', block_size => 127);
my @samples;
while (my $block = $next->()) { push @samples, @{$block} }
is_deeply(\@samples, $rtty->samples('A'), 'facade streaming');
is($rtty->decode($rtty->encode('a')),                              'A',  'facade notation');
is($rtty->decoder->decode_bits($rtty->bits('A'))->text,            'A',  'facade bits');
is($rtty->sampled_events('A', sample_rate => 8000)->{sample_rate}, 8000, 'facade sampled events');
done_testing;
