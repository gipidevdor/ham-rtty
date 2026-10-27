# Architecture

[Overview](../README.md) · [Task guide](usage.md) · [Examples](../examples/README.md) · [Contributing](../CONTRIBUTING.md)

- Text: `Encoder → Morse`, `Decoder → text`.
- Timing and synthesis: `Encoder → TimedEvents → SampledEvents → Generator`.
- Reception: `Audio reader → Detector → SampledEvents → Decoder → Result`.
- MIDI: timed or sampled events to SMF type 0.

## File convenience boundary

`write_wav(text, path)`, `write_midi(text, path)` and `read_wav(path)` open and
close their own handles. New output uses exclusive creation. With
`overwrite => 1`, data is written to a temporary sibling and renamed after
generation and close succeed.

Replacement preserves regular-file permission bits, but creates a new file
identity: ownership, ACLs and other hard links are not transferred. New files
use 0666 filtered through the process umask. Detected symlinks, including
dangling ones, are rejected. Inspection and rename are separate operations;
use a directory protected from concurrent writers.

On callback failure, the helper closes the handle, attempts to remove the new
output and rethrows the original error. Close failures become structured I/O
errors. Methods receiving caller-owned handles leave them open.

## Event boundaries

TimedEvents is `{ unit => 'us', segments => [...] }`. A segment contains
`state => 'on'|'off'` and positive integer `duration` in microseconds.
SampledEvents instead has `sample_rate` and positive integer `samples` per
segment. Empty sequences and leading/trailing OFF are legal; adjacent states
must alternate. Total duration cannot exceed 2**52 units. Sample rates are
integer Hz in 1000..384000. No input is modified.

Conversions round cumulative boundaries to nearest integer, halves upward.
They reject a conversion that would create a zero-length segment. Rounding
per segment would accumulate drift; rounding cumulative boundaries does not.
MIDI uses the same boundary rule at the encoded tempo and tick resolution.

The LIGHT word contains 31 mark/element-gap units and 19 spacing units when
its terminal word gap is included. For character rate `w` and effective rate
`e`, dot duration is `1,200,000/w` microseconds, and extended spacing unit is
`(60,000,000/e - 31*dot)/19`. Generated events omit the terminal word gap.

## Incremental objects

| Component | Input | Output | Retained data |
| --- | --- | --- | --- |
| Generator | Complete event sequence | Pull iterator of sample arrays | Event copy, position |
| Audio reader | Seekable WAV handle | Pull iterator of mono sample arrays | Chunk metadata and one block |
| Audio writer | Declared count, sample blocks | PCM bytes to caller handle | Counters, one block |
| Decoder | Canonical event blocks | Cumulative Result | Bounded canonical events |
| Detector | Mono sample blocks | Provisional/final Result | One partial frame and bounded frame powers |
| MIDI | Complete event sequence | Binary SMF or file write | Bounded track bytes |

An object starts READY, becomes ACTIVE when processing starts, and becomes
FINISHED at EOF/finish. Feed after finish is rejected. Resettable objects
return to READY; resetting a generator invalidates its existing iterator.
Finishing twice does not duplicate data. An I/O error makes a WAV writer
FAILED; replace it and its output rather than continuing a corrupt file.
Atomic text/MIDI operations have no incremental lifecycle. Validation errors
preserve object state. Caller-owned handles are never closed by the library.

With configured WPM, decoder snapshots include characters whose following gap
has closed; finish confirms the final group. Auto-timing and detector previews
can revise earlier text, timing and thresholds.

Snapshots cover the full retained history. Replace the previous snapshot
rather than appending it. Successful feeds invalidate the preview cache;
rejected feeds preserve it, and reset clears it. Request previews periodically
to avoid repeatedly processing the same history.

Internal snapshots share immutable segment records and copy the segment list.
Public Result construction validates and deep-copies caller data; accessors
return independent copies of reference fields.

## Reception assumptions

Samples advance on a fixed approximately 5 ms hop grid. Every candidate
frequency has two persistent constant-peak biquad band-pass sections in
transposed direct form II. Original code implements the mathematical BPF
coefficients in the [W3C Audio EQ Cookbook](https://www.w3.org/TR/audio-eq-cookbook/).
With `alpha = tan(pi * width / rate)`, `width` is the digital single-section
full half-power bandwidth; cascading narrows the combined response. The
nominal centre-frequency group delay of the cascade is `2 / alpha` samples.
The default width is `max(40, 4 * WPM)` Hz with a WPM hint, otherwise 180 Hz.
It balances rejection and keying transients; it is not a guarantee of separation.

Four filtered hops form a DC-removed Hann window, approximately 20 ms. Goertzel
measures each channel's tone power; a channel that fails acquisition keeps
its windowed energy but skips the recurrence. Acquisition separately examines
eight raw hops (40 ms): each hop supplies one Fourier projection per candidate
and guard frequency, and the eight projections are combined under a hop-wise
Hann taper with the window mean removed. The candidate power is compared
against the lower median of up to six neighboring guard powers, scaled by 1.3.
Guards are at offsets
±1, ±2 and ±3 times `max(100, 2 * frequency_step)` Hz, omitting frequencies
outside the sampled band. The default 12 dB power-ratio threshold gates the
filtered features. This is spectral contrast, not calibrated SNR. Guard geometry
and strong interference can still defeat it.

Accumulated channel energies rank local spectral maxima. Contrast, filtered
purity, keyed marks and timing determine acceptance. `channels()` exposes up
to eight Results, strongest accumulated energy first, separated by at least
`max(100, filter_bandwidth)` Hz to avoid duplicate adjacent-bin reports.
The primary API returns the first accepted Result, or a rejection Result.
A supplied frequency limits the bank to one channel. Different keyed tones
can be recovered simultaneously; co-channel sources cannot be unmixed.

Median smoothing, sustained-support peak caps, adaptive OFF noise and keyed
peak tracking with one-second decay and hysteresis reduce impulsive errors.
In an ON run whose power exceeds twice the seeded peak, hops below 22% of
its own top but still above that clamp are dropped, so a burst smeared by
the analysis window cannot pass as a mark while a genuine mark underneath
the burst stays keyed. Carrier intervals and sub-tolerance short marks are
excluded.
Valid multi-mark
Morse groups anchor margin cleanup; adjacent valid short letters and one
neighboring damaged multi-mark group are retained. Unsupported activity beyond
those margins is suppressed with a warning. Damaged interior groups remain
replacement characters. This generic timing heuristic can discard badly damaged
real edge characters and does not establish that decoded text is meaningful.

The symbolic decoder samples distinct mark widths with at most 128 timing
candidates, or uses supplied WPM. Both mark classes permit a dot estimate
that allows a common shaping/quantization offset. Without both classes,
automatic timing can remain ambiguous and text is suppressed.

Filter states and short raw/filtered histories persist across feeds. Finalization
adds bounded zero padding, shifts feature columns by rounded nominal window/
filter delay, then drops padding features. Actual input length and resource
accounting remain unchanged. Preview features are causal and uncompensated;
final event boundaries may change. The operation does not retain the full raw
recording. Feature storage is O(KN), bounded by candidate and frame limits.
Fresh analysis costs O(KN log N), with per-channel O(N) working memory;
unchanged snapshots are cached. Throttle previews, for example once a second.
Unlimited-duration reception is outside this version's contract.

## Detector power heuristics

The private lexical settings near the top of `lib/Ham/RTTY/Detector.pm` name the
acquisition and envelope-tracker settings. These module-private bindings are
initialized once and are not per-detector options. They operate on **power**,
not waveform amplitude. They are engineering heuristics, not values derived from
ITU Morse timing or a calibrated statistical noise model. The repository does
not provide a parameter-sweep study establishing that these values are optimal.
The rationale below explains their role and tradeoffs, not a mathematical
calibration. Naming them preserves the existing values and arithmetic.

| Named setting | Value | Role and tuning tradeoff |
| --- | ---: | --- |
| `GUARD_NOISE_MARGIN` | 1.3 | Multiplies the lower-median guard power before acquisition. Adds a conservative margin (about 1.14 dB) to that estimate; increasing it rejects more candidates, including weak genuine tones. It is not a proven bias correction for the guard median. |
| `ENVELOPE_NOISE_GATE_RATIO` | 12 | Keeps the switching threshold at least twelve times the **initial** channel noise floor, preventing the decaying tracker from admitting low-level activity. Increasing it can lose faint marks. This is a linear power ratio, about 10.8 dB, not the separate 12 dB `min_snr_db` default. |
| `TRACKED_PEAK_FLOOR_FRACTION` | 0.05 | Seeds and bounds the tracked peak at `floor + 0.05 * (seeded_peak - floor)`. Prevents peak decay from collapsing the relative threshold toward the noise floor; increasing it makes faded marks harder to retain. It is not a 5% amplitude cutoff or the final switching threshold. |
| `KEY_ON_FRACTION` / `KEY_HOLD_FRACTION` | 0.22 / 0.12 | Enter ON above 22% of the tracked peak-to-noise range, but retain ON down to 12%, subject to the initial-floor gate. This hysteresis reduces chatter and split marks. A higher entry fraction can miss weak attacks; a higher hold fraction can shorten tails or split fading marks. |
| `TRACKED_PEAK_CLAMP_RATIO` | 2 | Limits each observation used by the peak tracker to twice the seeded peak. The same boundary identifies an unusually strong run for burst trimming. Raising it lets impulses pull the tracker farther above message power. |
| `NOISE_UPDATE_THRESHOLD_FRACTION` | 0.25 | Allows noise updates only while OFF and below one quarter of the switching threshold. Keeps fading attacks and filter tails out of the noise estimate. Raising it admits more signal residue; lowering it leaves fewer background observations. |
| `NOISE_UPDATE_RATE` | 0.02 | Moves the noise estimate 2% toward each eligible OFF-hop observation. At nominal 5 ms hops, about 50 eligible observations give one e-fold of adaptation (about 0.25 seconds only if every hop qualifies). Faster adaptation also follows contamination faster. |
| `BURST_TRIM_FRACTION` | 0.22 | In an ON run whose maximum exceeds the peak clamp, suppresses hops below 22% of that run's maximum **only when they remain above the clamp**. This narrows a smeared strong burst while leaving message-level hops eligible. Raising it trims more of the burst and can remove genuine strong activity. |

The two 22% settings have separate meanings: one enters the ordinary keyed
state using a tracked peak and noise estimate; the other trims an exceptional
burst using that run's own maximum. Their equal numeric value does not make
them one parameter. Likewise, other 25% checks in purity/peak support are not
the OFF-noise-update rule.

For clarity, the switching rule is
`max(initial_floor * ENVELOPE_NOISE_GATE_RATIO,
tracked_noise + fraction * (tracked_peak - tracked_noise))`, where `fraction`
is the hold or entry fraction according to the preceding state. This gate is
separate from acquisition (`min_snr_db`) and subsequent sample-weighted mark
admission (`mark_snr_db`); both public options convert dB to power ratios with
`10 ** (dB / 10)`.

When tuning, run `t/27-mark-snr.t` for local-noise boundaries, partial-hop
weighting and weak/strong burst admission; `t/26-channel-reception.t` for
channel separation, interference and chunk/backend equivalence; and
`t/17-reception-matrix.t` for independent synthetic timing, fading and noise.
Check the real clips with `perl maint/reception-corpus.pl` as well. These are
regression evidence, not proof of optimal thresholds or general field accuracy.
Record any changed values with the competing signal/noise cases and compare
text, event boundaries and warnings across both backends and feed sizes.

## Optional PDL backend

The internal backend resolver accepts `perl`, `pdl`, and `auto`. Only the PDL backend
loads PDL; explicit selection fails early if unavailable. Facade construction
propagates selection to generation and PCM I/O, and reception inherits it
unless overridden. Symbolic encoding, events, decoding and MIDI remain shared.
The vector implementation uses double precision and public Perl arrays.
Detection uses squared sinusoidal projections, mathematically equivalent to
Goertzel power, with cached kernels per frame length and batches of at most
128 frames. Partial final hops enter the same fixed history/window and are flushed once.
Acquisition and biquad states are shared with the scalar pipeline; PDL batches
only the equivalent filtered projections. Acquisition projections and the
sample-by-sample biquad loops still run in Perl. Each PDL batch copies filtered
history windows into Perl arrays, constructs a PDL tensor and exports powers
and energies back to Perl arrays. There is no compiled PDL::PP filter-bank
kernel or persistent PDL feature store in the shipped implementation.

A 16-hop batch was tested in a temporary local probe; the shipped cap remains
128 hops. That experiment and proposed vectorized acquisition are separate
from [current release timings](benchmarks.md).
Existing validation precedes processing and retained history stays bounded.
