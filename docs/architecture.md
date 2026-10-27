# Architecture

[Overview](../README.md) · [API](../lib/Ham/RTTY.pm)

The facade composes independent encoders, decoders, generators and detectors.
No module depends on Ham::CW at runtime. Public API uses named arguments,
structured errors and deep-copy Result snapshots.

| Module | Responsibility |
| --- | --- |
| Baudot | Data-driven ITU/US tables and receiver shift state |
| Encoder | Text to shift codes, frames, bits and alternating runs |
| Decoder | Incremental UART sampling and ITA2 state |
| Events | Validation and cumulative-boundary conversions |
| Generator | Continuous-phase two-tone synthesis |
| Detector | Narrowband energy comparison, ATC, acquisition and UART |
| Audio | Streaming PCM 8/16/24-bit mono/stereo reader and mono writer |
| MIDI | Two-note type-0 debug rendering |
| Result / Error | Independent snapshots and structured exceptions |

The transmitter merges adjacent equal states and rounds cumulative event
boundaries. A phase accumulator changes its increment at tone transitions,
without phase reset. Audio and protected I/O retain the reference project's
contracts; signal encoding and reception are RTTY-specific.

Reception analyses 0.65-bit rectangular windows at approximately 12 hops per
bit. Goertzel estimates the two tone energies in Perl; PDL broadcasts both
sinusoidal projections in one operation. ATC tracks independently decaying
peaks with a shared floor. Search scores candidate tone pairs over an initial
half-second acquisition buffer. The selected pair remains fixed afterwards.

Decisions are timestamped at window centres and merged into sampled runs.
The shared event decoder detects MARK-to-SPACE, validates the start centre,
samples data centres and checks MARK at the stop centre. Framing errors warn
and release the synchroniser to seek a new start transition. Long stop MARK
runs are idle; stop duration does not need to equal the transmitter setting.

Only bounded acquisition, a partial analysis buffer and feature/run history
are retained. Results rebuild the UART interpretation from that history and
cache unchanged previews. No simultaneous stations, automatic baud/shift
identification, equalisation or diversity are provided.

`perl` is the default; `auto` chooses by availability only. PDL accelerates
projection, synthesis and PCM; state-machine work remains Perl. See measured
[benchmarks](benchmarks.md) and [verification](verification.md).
