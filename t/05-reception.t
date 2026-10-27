use 5.020;
use strict;
use warnings FATAL => 'all';
use Test::More;
use Ham::RTTY;
use Ham::RTTY::_Internal::Backend;
my @backends = ('perl');
push @backends, 'pdl' if Ham::RTTY::_Internal::Backend::resolve('auto') eq 'pdl';
srand 170;
my @alphabet = split //, "ABCDEFGHIJKLMNOPQRSTUVWXYZ 0123456789-?:'()/.,=+";
my $message  = 'CQ ' . join('', map { $alphabet[int rand @alphabet] } 1 .. 14);

for my $backend (@backends) {
    for my $rate (8000, 16000) {
        for my $baud (45.45, 50, 75) {
            for my $shift (170, 450, 850) {
                for my $stop (1, 1.5, 2) {
                    my $rtty = Ham::RTTY->new(
                        sample_rate => $rate,
                        baud        => $baud,
                        shift       => $shift,
                        stop_bits   => $stop,
                        backend     => $backend
                    );
                    my $name    = "$backend $rate Hz $baud baud $shift Hz stop $stop";
                    my $samples = $rtty->samples(lc $message);
                    my %receive = (baud => $baud, shift => $shift, backend => $backend);
                    is($rtty->decode_samples($samples, %receive)->text, $message, "$name samples");
                    is($rtty->decode_wav_bytes($rtty->wav_bytes(lc $message), %receive)->text,
                        $message, "$name WAV");
                }
            }
        }
    }
}
for my $backend (@backends) {
    my $low_rate = Ham::RTTY->new(
        sample_rate => 2000,
        mark        => 650,
        shift       => 170,
        baud        => 50,
        backend     => $backend
    );
    my $audio = $low_rate->samples('CQ TEST');
    for my $search (0, 1) {
        is($low_rate->decode_samples($audio, mark => 650, baud => 50, search => $search)->text,
            'CQ TEST', "$backend low-rate reception, search $search");
    }
    is(
        $low_rate->decode_wav_bytes($low_rate->wav_bytes('CQ TEST'), mark => 650, baud => 50)->text,
        'CQ TEST',
        "$backend low-rate WAV reception uses header rate"
    );
    my $ok = eval {
        $low_rate->detector(mark => 650, max_frequency => 900);
        1;
    };
    ok(!$ok, "$backend explicit search band above Nyquist remains invalid");
    is($@->code, 'RTTY_E_ARGUMENT', 'invalid band keeps stable argument error');
}
my $rtty    = Ham::RTTY->new(sample_rate => 8000);
my $samples = $rtty->samples($message);
for my $size (1, 137, 4096) {
    my $detector = $rtty->detector;
    for (my $i = 0; $i < @{$samples}; $i += $size) {
        my $end = $i + $size - 1;
        $end = $#{$samples} if $end > $#{$samples};
        $detector->feed([@{$samples}[$i .. $end]]);
    }
    is($detector->finish->text,     $message, "reception block independence $size");
    is($detector->result->complete, 1,        'final cached');
    ok(!eval { $detector->feed([]); 1 }, 'feed after finish');
    is($detector->reset->state, 'READY', 'reset');
}
for my $reverse (0, 1) {
    for my $mismatch (-0.02, 0, 0.02) {
        for my $offset (-20, 0, 20) {
            my $audio = $rtty->samples(
                $message,
                mark    => 2125 + $offset,
                reverse => $reverse,
                baud    => 45.45 * (1 + $mismatch)
            );
            is($rtty->decode_samples($audio, reverse => $reverse)->text,
                $message, "reverse $reverse mismatch $mismatch offset $offset");
        }
    }
}
srand 170;
my @noisy = map { $_ * 0.7 + (rand() - 0.5) * 0.2 } @{$samples};
is($rtty->decode_samples(\@noisy)->text, $message,
    'uniform white noise at theoretical 16.7 dB SNR');
my $silent = $rtty->decode_samples([(0) x 8000]);
is($silent->text,                '',                 'silence');
is($silent->warnings->[0]{code}, 'RTTY_W_NO_SIGNAL', 'no signal warning');
my $search = $rtty->decode_samples($rtty->samples($message, mark => 1900), search => 1);
is($search->text, $message, 'tone-pair search');
cmp_ok(abs($search->frequency - 1900), '<=', 10, 'searched mark');
done_testing;
