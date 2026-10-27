use strict;
use warnings;
use Test::More;
use Ham::RTTY;
use Ham::RTTY::Events qw(to_samples);
use File::Temp      qw(tempdir);
use File::Spec;
my $cw   = Ham::RTTY->new(sample_rate => 8000, frequency => 650);
my $base = $cw->events('SOS');
is_deeply(
    $cw->events('SOS', wpm => 40),
    Ham::RTTY->new(wpm => 40)->events('SOS'),
    'per-call event speed'
);
is_deeply($cw->events('SOS'), $base, 'override does not change object');
is($cw->encode('A!', unknown => 'skip'),       '.-',   'per-call symbol policy');
is($cw->decode('.-.-.', prefer_prosigns => 1), '<AR>', 'facade exposes prosign decoding');
is_deeply($cw->sampled_events('SOS'), to_samples($base, 8000), 'sample timing facade');
my $values = $cw->samples('SOS');
my $next   = $cw->stream_samples('SOS', block_size => 137);
my @streamed;
while (my $block = $next->()) { push @streamed, @{$block} }
is_deeply(\@streamed, $values, 'streamed samples equal collecting API');
ok(!defined $next->(), 'sample iterator EOF repeats safely');
is($cw->decode_samples($values, wpm => 20)->text, 'SOS', 'decode raw samples');
is($cw->decode_events($base,                      wpm => 20)->text, 'SOS', 'decode timed events');
is($cw->decode_events($cw->sampled_events('SOS'), wpm => 20)->text, 'SOS', 'decode sampled events');
my $detector = $cw->detector(wpm => 20);
$detector->feed($values);
is($detector->finish->text, 'SOS', 'detector factory inherits sample rate');
my $decoder = $cw->decoder(wpm => 20);
$decoder->feed($base);
is($decoder->finish->text, 'SOS', 'decoder factory');
my $bytes = $cw->wav_bytes('SOS', bits => 24, frequency => 700, wpm => 30);
is($cw->decode_wav_bytes($bytes, wpm => 30)->text, 'SOS', 'WAV bytes roundtrip with overrides');
is(substr($cw->midi_bytes('SOS', wpm => 30, note => 60), 0, 4), 'MThd', 'MIDI bytes');

for my $method (qw(samples stream_samples wav_bytes midi_bytes events sampled_events encode)) {
    eval { $cw->$method('SOS', typo => 1) };
    is((ref($@) ? $@->code : "$@"), 'RTTY_E_ARGUMENT', "$method rejects unknown option");
    eval { $cw->$method('SOS', wpm => 20, wpm => 30) };
    is((ref($@) ? $@->code : "$@"), 'RTTY_E_ARGUMENT', "$method rejects duplicate option");
}
for my $bad (undef, [], {}) {
    eval { $cw->decode_wav_bytes($bad) };
    is((ref($@) ? $@->code : "$@"), 'RTTY_E_ARGUMENT', 'WAV bytes input validation');

}
for my $bad (undef, {}, 'not samples') {
    eval { $cw->decode_samples($bad) };
    is((ref($@) ? $@->code : "$@"), 'RTTY_E_ARGUMENT', 'sample input validation');
}
eval { $cw->stream_samples('SOS', block_size => 0) };
is((ref($@) ? $@->code : "$@"), 'RTTY_E_ARGUMENT', 'stream block size validation');
eval { $cw->samples('SOS', max_samples => 10) };
is((ref($@) ? $@->code : "$@"), 'RTTY_E_RESOURCE', 'sample ceiling exposed');
my $root  = tempdir(CLEANUP => 1);
my $path  = File::Spec->catfile($root, 'raw.wav');
my $audio = Ham::RTTY::Audio->new(block_samples => 137);
$audio->write_file($path, $values, sample_rate => 8000, bits => 24);
my $raw = $audio->read_file($path);
is($raw->{sample_rate},       8000,              'raw WAV file metadata');
is(scalar @{$raw->{samples}}, scalar @{$values}, 'raw WAV sample count');
my @blocks;
my $info = $audio->read_blocks(
    $path,
    sub {
        my ($block, $metadata) = @_;
        is($metadata->{sample_rate}, 8000, 'block metadata') unless @blocks;
        push @blocks, @{$block};
    }
);
is_deeply(\@blocks, $raw->{samples}, 'bounded WAV callbacks match collecting read');
is($info->{sample_count}, scalar @blocks, 'stream returns metadata');
eval { $audio->read_blocks($path, 'not a callback') };
is((ref($@) ? $@->code : "$@"), 'RTTY_E_ARGUMENT', 'callback validated');
my $midi = File::Spec->catfile($root, 'raw.mid');
my $smf  = Ham::RTTY::MIDI->new;
is($smf->write_file($midi, $base), length($smf->encode($base)), 'custom events to MIDI file');
eval { $smf->write_file($midi, $base) };
is((ref($@) ? $@->code : "$@"), 'RTTY_E_IO', 'advanced MIDI file protection');
is_deeply(
    $cw->encoder(wpm => 40)->events('SOS'),
    $cw->events('SOS', wpm => 40),
    'encoder factory applies timing overrides'
);
is_deeply($cw->generator->generate($base), $values, 'generator factory for custom events');
my $stream_path = File::Spec->catfile($root, 'stream.wav');
$audio->write_blocks(
    $stream_path, $cw->stream_samples('SOS', block_size => 137),
    sample_rate  => 8000,
    sample_count => scalar @{$values},
    bits         => 24
);
is_deeply($audio->read_file($stream_path)->{samples},
    $raw->{samples}, 'bounded WAV writing matches collecting write');
my $failed_path = File::Spec->catfile($root, 'short.wav');
$next = $cw->stream_samples('SOS');
eval { $audio->write_blocks($failed_path, $next, sample_count => 1, sample_rate => 8000) };
is((ref($@) ? $@->code : "$@"), 'RTTY_E_ARGUMENT', 'incorrect declared sample count rejected');
ok(!-e $failed_path, 'failed streaming output cleaned');
eval { $audio->write_blocks($failed_path, 1, sample_count => 0) };
is((ref($@) ? $@->code : "$@"), 'RTTY_E_ARGUMENT', 'stream source validated');
my $callbacks = 0;
$audio->read_blocks(
    $path,
    sub {
        my ($block, $metadata) = @_;
        is($metadata->{sample_rate}, 8000, 'metadata isolated between callbacks')
            if ++$callbacks <= 2;
        $metadata->{sample_rate} = 123;
    }
);
is($cw->decode_samples([])->text,                   '', 'empty samples are legal');
is($cw->decode_wav_bytes($cw->wav_bytes(''))->text, '', 'empty WAV bytes are legal');
eval { $cw->decode_wav_bytes('not a WAV') };
ok(ref($@) && $@->isa('Ham::RTTY::Error'), 'malformed WAV bytes structured error');
is_deeply($cw->samples('SOS'), $values, 'generation overrides leave defaults intact');
eval { $cw->decode_wav_bytes("\x{2603}") };
is((ref($@) ? $@->code : "$@"), 'RTTY_E_ARGUMENT', 'Unicode text is not binary WAV data');
$audio->write_file($path, $values, sample_rate => 8000, bits => 16, overwrite => 1);
is($audio->read_file($path)->{bits}, 16, 'raw WAV explicit replacement');
$smf->write_file($midi, $base, overwrite => 1);
ok(-s $midi, 'custom MIDI explicit replacement');
$audio->write_blocks(
    $stream_path, $cw->stream_samples('SOS'),
    sample_rate  => 8000,
    sample_count => scalar @{$values},
    overwrite    => 1
);
is($cw->read_wav($stream_path)->text, 'SOS', 'stream output explicit replacement');
done_testing;
