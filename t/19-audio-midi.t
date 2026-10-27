use strict;
use warnings FATAL => 'all';
use Test::More;
use File::Temp qw(tempdir);
use Ham::RTTY;
use Ham::RTTY::_Internal::Backend;
my $dir    = tempdir(CLEANUP => 1);
my $audio  = Ham::RTTY::Audio->new;
my @values = (-0.75, 0, 0.75);
$audio->write_file("$dir/raw.wav", \@values, sample_rate => 8000);
is_deeply($audio->read_file("$dir/raw.wav")->{samples}, \@values, 'Audio paths');
$audio->write_file("$dir/raw.wav", \@values, sample_rate => 8000, overwrite => 1);
my @blocks = ([0, 0.5], [-0.5]);
$audio->write_blocks(
    "$dir/blocks.wav", sub { return shift @blocks },
    sample_rate  => 8000,
    sample_count => 3
);
is(scalar @{$audio->read_file("$dir/blocks.wav")->{samples}}, 3, 'bounded block writer');
ok(!eval { $audio->write_blocks("$dir/bad.wav", []); 1 }, 'block source validation');
ok(!eval { $audio->read_blocks("$dir/raw.wav", []);  1 }, 'callback validation');
ok(!eval { Ham::RTTY::Audio->new(stereo => 'bad');   1 }, 'stereo policy');
ok(!eval { $audio->reader(undef);                    1 }, 'reader handle');
ok(!eval { $audio->writer(undef, sample_count => 0); 1 }, 'writer handle');
my $rtty   = Ham::RTTY->new;
my $midi   = Ham::RTTY::MIDI->new;
my $events = $rtty->events('CQ');
$midi->write_file("$dir/raw.mid", $events);
$midi->write_file("$dir/raw.mid", $events, overwrite => 1);
ok(-s "$dir/raw.mid", 'MIDI path writer');
is(substr($midi->encode($rtty->sampled_events('CQ')), 0, 4), 'MThd', 'sampled MIDI');
is(
    substr(
        $midi->encode(
            {unit => 'bits', baud => 50, segments => [{state => 'mark', duration => 1.5}]}
        ),
        0, 4
    ),
    'MThd',
    'fractional-bit MIDI'
);

for my $case (
    [{unit => 'us', segments => [{state => 'mark', duration => 1}]}, 'RTTY_E_TIMING', {}],
    [$events, 'RTTY_E_RESOURCE', {max_bytes => 64}],
    [{unit => 'us', segments => [{state => 'mark', duration => 2**52}]}, 'RTTY_E_TIMING', {}]
    )
{
    eval { Ham::RTTY::MIDI->new(%{$case->[2]})->encode($case->[0]) };
    is(ref($@) ? $@->code : '', $case->[1], 'MIDI timing/resource limits');
}
ok(!eval { $midi->write(undef, $events); 1 }, 'MIDI handle validation');
my $wav  = $rtty->wav_bytes('CQ');
my $tail = $rtty->decode_wav_bytes(
    $wav . 'extra',
    stereo        => 'left',
    max_bytes     => 64000000,
    block_samples => 137
);
is($tail->warnings->[0]{code}, 'RTTY_W_WAV_TRAILING', 'facade propagates trailing warning');
is($rtty->decode_events($events)->text,       'CQ',   'facade events');
is($rtty->sampled_events('A')->{sample_rate}, 16000,  'default sampled rate');
ok(!eval { $rtty->decode_wav_bytes("\x{100}"); 1 }, 'nonbyte WAV rejected');
my $det = $rtty->detector(max_segments => 1);
ok(!eval { $det->feed([(0) x 8000]); 1 }, 'detector run preflight limit');
ok(!eval { Ham::RTTY::Detector->new(sample_rate => 5000, max_frequency => 2400); 1 },
    'search band Nyquist validation');

# Exercise optional-backend absence without requiring a separate installation.
{
    local $INC{'Ham/RTTY/_Internal/PDL.pm'};
    delete $INC{'Ham/RTTY/_Internal/PDL.pm'};
    local @INC = (sub { die "PDL deliberately unavailable\n" });
    is(Ham::RTTY::_Internal::Backend::resolve('auto'), 'perl', 'auto falls back by availability');
    ok(!eval { Ham::RTTY::_Internal::Backend::resolve('pdl'); 1 },
        'explicit unavailable PDL rejected');
}
if (Ham::RTTY::_Internal::Backend::resolve('auto') eq 'pdl') {
    my $pdl_audio = Ham::RTTY::Audio->new(backend => 'pdl');
    is_deeply(Ham::RTTY::_Internal::PDL::decode_pcm('', 16, 1, 'mix'), [], 'empty PDL PCM');
    is_deeply([Ham::RTTY::_Internal::PDL::quantize([], 32768)],        [], 'empty PDL quantizer');
    for my $bits (8, 16, 24) {
        for my $policy (qw(mix left right)) {
            my $raw =
                  $bits == 8  ? pack('CC', 160, 96)
                : $bits == 16 ? pack('s<s<', 8192, -8192)
                :   substr(pack('V', 2097152), 0, 3) . substr(pack('V', 14680064), 0, 3);
            my $values = Ham::RTTY::_Internal::PDL::decode_pcm($raw, $bits, 2, $policy);
            is(
                $values->[0],
                $policy eq 'mix' ? 0 : $policy eq 'left' ? 0.25 : -0.25,
                "PDL stereo $bits $policy"
            );
        }
    }
}
done_testing;
