# Reference corpus

[Overview](../README.md) · [Reception guide](../docs/usage.md#simultaneous-stations) · [Verification](../docs/verification.md) · [Recording licenses](real/LICENSES.md)

`vectors.json` contains fixed symbolic expectations, independent of the
implementation's table. The symbol reference is ITU-R M.1677-1 (2009), Annex 1.

`sos-650hz-20wpm.wav` is synthetic SOS, 650 Hz, 20 WPM, 8000 Hz mono signed
16-bit PCM, amplitude 0.6, with 180 ms leading and trailing silence.
`perl maint/build-corpus.pl` builds it from a fixed schedule using core Perl,
independently of Ham::RTTY and the test signal helper. Expected text: `SOS`;
sample count: 15840. It uses hard keying rather than a raised-cosine envelope.

The fixture and builder are original project material under the Artistic
License 2.0. Third-party radio recordings are listed below. Separate synthetic
tests cover noise, fading, impulses and small frequency variations.

`reception.json` defines a deterministic synthetic reception matrix using the
independent fixed SOS schedule in `t/lib/Reference.pm`. It combines 5–60 WPM,
8000/11025/16000 Hz sampling, off-grid tones, fading, low amplitude, seeded
noise and DC offset, plus silence/noise rejection. `t/17-reception-matrix.t`
checks text, tone tolerance, warnings and exact event equivalence for 137- and
4096-sample feeds with every available backend.

## Real received audio

`real.json` and `real/*.wav` add four clips from three received radio-beacon
recordings, with per-file attribution, audio licenses, source hashes and
transformations in [real/LICENSES.md](real/LICENSES.md). These files retain
their own CC0/CC BY-SA terms. The test suite measures character error rate
(CER), rather than requiring exact text on every recording. Recorded regression
budgets are separate from the quality target. The 2026-10-25 local run on
revision `85eb8f3` recovered all four clip references with CER 0%, with and
without a speed hint, and no warnings. These eight checks cover four short
automated-beacon clips. See the
[raw results](../docs/current-results.json) and [verification record](../docs/verification.md).
Run `perl maint/reception-corpus.pl` to repeat the checks.

Synthetic tests cover recovery behind a stronger unkeyed carrier and
independent, simultaneous SOS/CQ signals at unequal levels with added noise.
The channel test also checks independent 20/25 WPM estimation, 150 Hz separation
with explicit speed, backend/chunk equivalence and filter response.
A separate synthetic schedule varies mark/gap lengths by up to 12%.
Human-keyed QSOs and field error rates remain unmeasured.

## Admission to the release corpus

A new recording needs an explicit free license permitting redistribution and
adaptation, an identified author/source and a record of any conversion or crop.
Public download access alone is not a license. Preserve the original terms and
review obligations before adding it to the inventory or MANIFEST. The author
check compares distributed audio with the reviewed inventory, verifies hashes
and requires license/attribution evidence and shipped legal texts. Unverified
local recordings are excluded; they are not examples or release fixtures.
