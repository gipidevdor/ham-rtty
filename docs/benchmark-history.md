# Benchmark history

[Overview](../README.md) · [Task guide](usage.md) · [Examples](../examples/README.md) · [Contributing](../CONTRIBUTING.md)

These sections retain measurements from their stated dates and source revisions.
They are not fresh results for the current checkout. See
[current measurements](benchmarks.md). The older platform tables predate the
channelized receiver; the later local section identifies its own source.
PDL is optional and backend selection uses availability, not these timings.

## Cross-platform comparison

The platform observations come from commit
`4e0a7e79a8e5d5fa76040d89d8c852c603667d67`, in
[run 40086118418](https://github.com/gipidevdor/ham-rtty/actions/runs/40086118418).
The benchmark generates and detects `CQ CQ DE TESTCALL` at 8000 Hz, either as
one sample array or 4096-sample feeds. PCM tests use one second of mono audio
at 8000 Hz. They include WAV headers, validation and public array conversion,
but exclude physical disk I/O. Each case warms up once and runs for at least
one wall-clock second, completing any operation already in progress.
The `benchmark-*` artifacts record environment, rates, elapsed time and counts.

### Ratios

Each cell is PDL calls/second divided by Perl calls/second on the same runner.
Values above 1 favour PDL; values below 1 favour Perl. These are short,
single-run observations on shared hosted machines. Small differences and
differences between runs should not be treated as stable backend rankings.

| Operation | Linux | macOS ARM64 | macOS Intel | Windows | Linux minimum |
| --- | ---: | ---: | ---: | ---: | ---: |
| Audio generation | 4.71x | 3.73x | 6.00x | 3.54x | 3.60x |
| Detection, complete array | 5.10x | 6.84x | 6.39x | 4.86x | 5.97x |
| Detection, 4096-sample feeds | 5.32x | 3.96x | 6.62x | 4.29x | 5.01x |
| PCM WAV read, 8-bit | 0.96x | 1.64x | 1.11x | 0.75x | 0.95x |
| PCM WAV read, 16-bit | 1.15x | 0.93x | 1.16x | 0.88x | 1.05x |
| PCM WAV read, 24-bit | 1.16x | 0.77x | 1.21x | 1.13x | 0.99x |
| PCM WAV write, 8-bit | 1.39x | 1.05x | 1.54x | 1.35x | 1.41x |
| PCM WAV write, 16-bit | 1.46x | 1.82x | 1.60x | 1.39x | 1.48x |
| PCM WAV write, 24-bit | 1.39x | 1.22x | 1.41x | 1.25x | 1.31x |

In these historical cases, PDL gave a substantial synthesis and detection benefit.
PCM conversion has a smaller, workload-dependent benefit; several cases
are slower with PDL. The automatic selector currently chooses according
to availability, not according to these timing results.

The five `benchmark-*` artifacts on the [run page](https://github.com/gipidevdor/ham-rtty/actions/runs/40086118418)
contain absolute rates and the underlying iteration counts, elapsed times
and environment metadata. They allow the ratios to be checked without
copying console logs into the release notes.

## Message length and elapsed time (local, 2026-10-24)

The measurements below use the literal message `CQ DE TESTCALL`, repeated
one, two, four, eight or twelve times with one separating space. Message
length is the actual character count including spaces, and audio duration
comes from the generated events. No reference-word equivalence is used.

The sample rate was the default 16000 Hz at 20 WPM, on macOS ARM64 with
Perl 5.44.0 and PDL 2.106. Each processing time is the median of three
new runs, in seconds.

| Repeated messages | Characters, including spaces | Audio duration | Generate, Perl | Generate, PDL | Analyze, Perl | Analyze, PDL |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 14 | 7.14 | 0.076 | 0.011 | 0.381 | 0.056 |
| 2 | 29 | 14.70 | 0.154 | 0.024 | 0.782 | 0.112 |
| 4 | 59 | 29.82 | 0.310 | 0.050 | 1.580 | 0.230 |
| 8 | 119 | 60.06 | 0.619 | 0.104 | 3.186 | 0.471 |
| 12 | 179 | 90.30 | 0.935 | 0.158 | 4.781 | 0.706 |

Generation measures sample synthesis, including generator construction.
Analysis measures 4096-sample feeds and finalization with the default
frequency search grid; detector construction is outside that timer.
The audio is already available in memory. PCM conversion, file I/O and
live reception time are excluded. These are measured cases, not estimates
extrapolated from the short CI benchmark.

Default reception retains at most 24000 frames, approximately 120 seconds
including silence. Longer recordings require a larger explicit `max_frames`
and more retained memory. The time needed to transmit or receive the audio
in real time remains its full audio duration.

## Repeat on a current checkout

From the repository root, `perl maint/benchmark.pl --help` describes configurable
workloads, complete WAV operations and snapshot measurements.
`perl maint/benchmark-platforms.pl --help` describes the platform comparison.
[Earlier raw local observations](benchmark-results.json) are also retained;
they predate subsequent reception corrections. Always record source revision,
Perl/PDL versions, workload, block size and environment with new timings.

## Local observations before CPAN preparation, 2026-10-25

Measured source: `85eb8f3fce614d30cb53eaeb0da6b978dbc3dacc`.
Environment: macOS ARM64, Perl 5.44.0, PDL 2.106. The
[raw measurement record](current-results.json) includes full environment details,
commands, CPU and wall totals, corpus results and SHA-256 hashes of measured
modules, tools and recording inputs. This update does not change the
measured numerical implementation. Command-help and example-interface
refinements do not alter these numerical paths.

The workload is `CQ CQ DE TESTCALL`, 20 WPM, 650 Hz, 8,000 samples/second:
73,440 samples, or **9.18 seconds of audio**. The sample receiver is fed in
4,096-sample blocks. Each table entry is total wall time divided by three
iterations; it is an arithmetic mean, not a median or a percentile. Workloads
were run sequentially without concurrent project tests or coverage collection.

| Operation | Perl | PDL |
| --- | ---: | ---: |
| Generate samples | 0.042 s | 0.012 s |
| Receive samples, tone search | 2.877 s | 3.166 s |
| Generate WAV | 0.076 s | 0.029 s |
| Decode WAV, tone search | 2.909 s | 3.591 s |
| Receive samples, known tone | 0.295 s | 0.252 s |
| Decode WAV, known tone | 0.303 s | 0.263 s |

In this local workload, PDL generates samples and WAV faster. With automatic
tone search it receives samples and decodes WAV slower than Perl. With the
650 Hz tone supplied, PDL is modestly faster for reception. Knowing the tone
reduces processing time substantially for both backends. These observations
are specific to this signal, environment and measurement protocol.

`perl` remains the default. `auto` selects PDL when available, regardless of
speed. Choose a backend using measurements of the operation and hints your
application actually uses. No universal backend speedup is claimed.
