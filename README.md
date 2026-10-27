# Ham::RTTY

RTTY, from text to signal and back.

[Usage](docs/usage.md) · [API](lib/Ham/RTTY.pm) · [Verification](docs/verification.md) · [Contributing](CONTRIBUTING.md)

Encode ITA2 text, inspect start-stop events, generate continuous-phase AFSK,
and receive PCM WAV. Perl 5.20 or later; core runtime dependencies only.
PDL 2.081 or later is optional. Author: Giacomo Picchiarelli.

This is a 0.01 development candidate. It is **not release-qualified** while
any required gate in [verification](docs/verification.md) remains open.

```sh
perl Makefile.PL
make
make test
perl -Ilib bin/ham-rtty encode "CQ 123"
perl -Ilib bin/ham-rtty wav --output cq.wav "CQ TEST"
perl -Ilib bin/ham-rtty receive --baud 45.45 cq.wav
```

```perl
use strict;
use warnings;
use Ham::RTTY;
my $rtty = Ham::RTTY->new(baud => 50);
my $bytes = $rtty->wav_bytes('CQ 123');
my $result = $rtty->decode_wav_bytes($bytes, baud => 50);
print $result->text, "\n";
warn "$_->{code}: $_->{message}\n" for @{$result->warnings};
```

| Operation | Entry point |
| --- | --- |
| Text and shift codes | `encode`, `decode` |
| Framed bits and exact timing | `bits`, `events`, `decode_events` |
| AFSK samples | `samples`, `stream_samples`, `decode_samples` |
| PCM WAV | `wav_bytes`, `write_wav`, `read_wav` |
| Debug MIDI | `midi_bytes`, `write_midi` |

Defaults: 45.45 baud, 2125 Hz MARK, +170 Hz SPACE, 1.5 stop bits, ITU ITA2,
USOS enabled, 16 kHz mono, amplitude 0.8. Reception uses configured baud;
measured timing is diagnostic only. Stop bits, tones and polarity are explicit.
No simultaneous stations, automatic baud/shift identification, equalisation,
diversity or frequency-transition shaping. No playback or radio control.

Output paths are protected unless `overwrite => 1` or `--overwrite` explicitly
requests replacement. Replacement uses a temporary sibling and rename.

See [architecture](docs/architecture.md), [benchmarks](docs/benchmarks.md),
[standards and provenance](docs/standards.md), [security CI](docs/security-ci.md) and [recording provenance](corpus/real/LICENSES.md).
Code and documentation use [Artistic 2.0](LICENSE); see [NOTICE](NOTICE).
