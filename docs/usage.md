# Usage

[Overview](../README.md) · [API](../lib/Ham/RTTY.pm) · [Examples](../examples/README.md)

## Text and timing

```perl
use strict;
use warnings;
use Ham::RTTY;
my $rtty = Ham::RTTY->new(baud => 50, stop_bits => 1.5);
my $notation = $rtty->encode('cq 123');
print $notation, "\n";
print $rtty->decode($notation), "\n";
my $events = $rtty->events('CQ 123');
print $rtty->decode_events($events, baud => 50)->text, "\n";
```

Notation contains numeric five-bit codes, most significant digit first, and
`[FIGS]`/`[LTRS]` markers. The `bits` method instead returns transmitted order:
start 0, five LSB-first data bits, stop 1. A 1.5-bit stop rounds up to two digits
in logical strings; use frames or events for exact duration.

ITA2 follows [ITU-T S.1](https://www.itu.int/rec/T-REC-S.1-199303-I/en).
ASCII lowercase is uppercased. Unsupported characters raise `RTTY_E_SYMBOL`;
`lenient => 1` substitutes `?`, with `RTTY_W_SYMBOL` in the Encoder Result.
No transliteration is applied. CR, LF, BELL, NULL and WRU use U+000D, U+000A,
U+0007, U+0000 and U+0005 respectively. Reserved national combinations are
unassigned in the ITU table. The US table differs in FIGS as follows:

| Letter position | ITU | US |
| --- | --- | --- |
| D | WRU | $ |
| F | reserved | ! |
| G | reserved | & |
| H | reserved | # |
| J | BELL | apostrophe |
| S | apostrophe | BELL |
| V | = | ; |
| Z | + | double quote |

USOS defaults on at both transmitter and receiver: SPACE returns the receiver
to LTRS; the encoder sends FIGS again when subsequent figures need it.
Set `usos => 0` on both ends for persistent shift state.

## Audio

```perl
use strict;
use warnings;
use Ham::RTTY;
my $rtty = Ham::RTTY->new(baud => 50, mark => 2125, shift => 450);
my $wav = $rtty->wav_bytes('CQ TEST 123', bits => 24);
my $result = $rtty->decode_wav_bytes($wav, baud => 50, mark => 2125, shift => 450);
print $result->text, "\n";
warn "$_->{code}: $_->{message}\n" for @{$result->warnings};
```

Standard speeds include 45.45, 50, 56.25, 75, 100 and 110 baud; accepted range
20..300 is an input contract, not a measured accuracy claim. Bit period is
1/baud seconds. MARK and SPACE must lie in 300..3000 Hz and below Nyquist.
Typical shifts are 170, 425, 450 and 850 Hz. MARK is the lower audio tone by
default; `reverse => 1` swaps tones. USB preserves the frequency ordering at
RF; LSB reverses it relative to audio. Match the radio and source polarity.

AFSK phase is continuous across transitions. Raised-cosine frequency shaping
is not implemented. Generation defaults to 0.1 seconds of MARK before/after
nonempty text. There is no automatic playback or device keying.

## Streaming

```perl
use strict;
use warnings;
use Ham::RTTY;
my $rtty = Ham::RTTY->new(sample_rate => 8000);
my $next = $rtty->stream_samples('CQ 73', block_size => 4096);
my $detector = $rtty->detector(sample_rate => 8000, baud => 45.45);
while (my $samples = $next->()) { $detector->feed($samples) }
my $result = $detector->finish;
print $result->text, "\n";
```

Results are cumulative independent snapshots. Replace previous text; do not
append snapshots. Check warnings. `finish` is idempotent; `feed` after finish
raises `RTTY_E_STATE`. `reset` discards history, keeping configuration.
Receiver input is incremental, with bounded feature/run history. The current
conservative resource preflight limits accepted hop count as well as runs.

Known baud is required for reception in 1.0: there is no auto-baud mode.
`measured_bit_period` is a median of observed one-bit run durations, not a
command to change baud. `search => 1` estimates a tone pair once within the
configured band and shift. It does not identify shift or separate stations.
ATC defaults on and corrects unequal tone peaks; it is not equalisation.

## Files and command line

```sh
perl -Ilib bin/ham-rtty help receive
perl -Ilib bin/ham-rtty events --baud 50 "CQ"
perl -Ilib bin/ham-rtty wav --output cq.wav --baud 50 "CQ 123"
perl -Ilib bin/ham-rtty receive --baud 50 --json cq.wav
perl -Ilib bin/ham-rtty midi --output cq.mid "CQ 123"
```

MIDI is a two-note visual/debug rendering (MARK 77, SPACE 79 by default).
It is type 0 with one track; MIDI tempo changes tick mapping, not baud.

Text uses strict UTF-8. Binary output requires `--output FILE` or `--output -`.
`--input FILE` and positional text are mutually exclusive. Text/JSON goes to
stdout, diagnostics to stderr. Paths use exclusive creation; `--overwrite`
uses a temporary sibling and rename. Failed replacement preserves old content.

Exit status: 0 success; 1 no received text or warnings under `--strict`;
2 invalid usage/options; 3 invalid data, resource or I/O error; 4 internal error.
Windows installation provides `ham-rtty.bat` through MakeMaker's launcher.
