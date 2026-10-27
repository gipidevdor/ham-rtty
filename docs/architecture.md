# Architecture

[Overview](../README.md) · [Task guide](usage.md) · [Examples](../examples/README.md) · [Contributing](../CONTRIBUTING.md)

- Text: `Encoder → ITA2 codes`, `Decoder → text`.
- Timing and synthesis: `Encoder → TimedEvents → SampledEvents → Generator`.
- Reception: `Audio reader → Detector → SampledEvents → Decoder → Result`.
- MIDI: timed or sampled events to SMF type 0.

## File convenience boundary

`write_wav(text, path)`, `write_midi(text, path)` and `read_wav(path)` open and
close their own handles. New output uses exclusive creation. With
`overwrite => 1`, data is written to a temporary sibling and renamed after
generation and close succeed.

Replacement preserves regular-file permission bits but creates a new file
identity. Ownership, ACLs and other hard links are not transferred. New files
use 0666 filtered through the process umask. Detected symlinks, including
dangling ones, are rejected. Inspection and rename are separate operations;
use a directory protected from concurrent writers.

On callback failure, the helper closes the handle, attempts to remove the new
output and rethrows the original error. Close failures become structured I/O
errors. Methods receiving caller-owned handles leave them open.

## Event boundaries

TimedEvents is `{ unit => 'us', segments => [...] }`. A segment contains
`state => 'mark'|'space'` and positive integer `duration` in microseconds.
SampledEvents instead has `sample_rate` and positive integer `samples` per
segment. Empty sequences and leading/trailing MARK are valid; adjacent states
must alternate. Total duration cannot exceed 2**52 units. Sample rates are
integer Hz in 1000..384000. Input sequences are not modified.

Timed events also accept seconds (`unit => 's'`) or fractional bits
(`unit => 'bits'`, with explicit `baud`). Conversions round cumulative
boundaries to nearest integer, halves upward. They reject a conversion that
would create a zero-length segment. MIDI uses the same boundary rule at the
encoded tempo and tick resolution.

The encoder emits one SPACE start bit, five data bits LSB first and MARK stop
of 1, 1.5 or 2 bits. It merges adjacent equal states before returning events.
Logical bit strings round a 1.5-bit stop up to two digits; frames and events
retain the fractional duration. A phase accumulator advances through both
tones, changing its increment at each transition. No frequency-transition
shaping is applied.

## Incremental objects

| Component | Input | Output | Retained data |
| --- | --- | --- | --- |
| Generator | Complete event sequence | Pull iterator of sample arrays | Event copy, position and phase |
| Audio reader | Seekable WAV handle | Pull iterator of mono sample arrays | Chunk metadata and one block |
| Audio writer | Declared count, sample blocks | PCM bytes to caller handle | Counters and one block |
| Decoder | Canonical event blocks | Cumulative Result | Bounded canonical events and shift state |
| Detector | Mono sample blocks | Provisional/final Result | Acquisition buffer, partial window and bounded decisions |
| MIDI | Complete event sequence | Binary SMF or file write | Bounded track bytes |

An object starts READY, becomes ACTIVE when processing starts, and becomes
FINISHED at EOF/finish. Feed after finish is rejected. Resettable objects
return to READY; resetting a generator invalidates its existing iterator.
Finishing twice does not duplicate data. An I/O error makes a WAV writer
FAILED; replace it and its output rather than continuing a corrupt file.
Textual notation and MIDI operations have no incremental lifecycle.

Snapshots cover the full retained history. Replace the previous snapshot
rather than appending it. The detector caches unchanged previews; accepted
feeds clear that cache. Public Result construction validates and deep-copies
caller data, and reference-valued accessors return independent copies.

## Reception assumptions

The detector analyses rectangular windows of approximately 0.65 bit, advancing
about 1/12 bit per hop. Perl uses a Goertzel recurrence at each of the two
frequencies. PDL evaluates both sinusoidal projections in one broadcast.
Neither path retains the complete raw recording.

Automatic threshold correction tracks independently decaying tone peaks.
Each peak decays by a factor of 0.999 per hop and is bounded below by one tenth
of the current window's stronger tone. The normalized energies determine
MARK or SPACE. Disabling ATC compares the uncorrected energies.

Optional search scores candidate tone pairs over the first half second using
the configured band, shift and grid step. The selected pair remains fixed.
Search does not identify baud or shift automatically.

Decisions are timestamped at window centres and merged into sampled runs.
The event decoder detects MARK-to-SPACE, validates the start centre, samples
five data centres and checks MARK at the stop centre. A bad stop increments
the framing-error count, records a warning and releases the synchroniser.
A partial frame at EOF records a separate warning. Long stop MARK runs are
idle and do not require an exact transmitter stop-length setting.

Reception handles one station. There is no equalisation or diversity.
Interference, fading and uncertain parameters can cause incorrect or missing
text. Synthetic tests and off-air recordings are reported separately in the
[verification record](verification.md).

## Optional numerical backend

`perl` is the default. `auto` selects PDL by availability only. PDL accelerates
projections, synthesis and PCM conversion; UART state, validation, acquisition
control and run construction remain Perl. See the
[measured performance](benchmarks.md) for operation-specific results.
