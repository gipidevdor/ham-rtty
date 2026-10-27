# Measured performance

[Overview](../README.md) · [Task guide](usage.md) · [Examples](../examples/README.md) · [Verification](verification.md)

## Current local measurements, 2026-10-25

Measured source: `c635a8ad588558a2d12bb0557d863cd571b61349`.
Environment: macOS ARM64, Perl 5.44.0, PDL 2.106.
[Raw results](performance-results.json) include commands, sample counts,
CPU/wall totals, ratios and source hashes. These runs use the shipped implementation.

All cases generate `CQ CQ DE TESTCALL` at 20 WPM and 650 Hz: **9.18 seconds
of audio**, fed in 4,096-sample blocks. Searches cover 300–1500 Hz at 50 Hz
spacing, or 25 candidates. The known-tone case supplies 650 Hz but no speed
hint to reception. Times are the mean of three calls. Workloads ran sequentially,
without concurrent tests or coverage collection.

### Sample reception

`R` is processing seconds divided by audio seconds. Lower is better; `R < 1`
means this in-memory recording was processed faster than playback duration.
Its inverse, `1/R`, is audio seconds processed per wall second. Live capture
latency is excluded.

| Workload | Perl time | PDL time | Perl R | PDL R |
| --- | ---: | ---: | ---: | ---: |
| 8 kHz, tone search (25 candidates) | 2.885 s | 3.127 s | 0.314 | 0.341 |
| 8 kHz, known 650 Hz tone (1 candidate) | 0.299 s | 0.251 s | 0.033 | 0.027 |
| 16 kHz, tone search (25 candidates) | 5.284 s | 6.039 s | 0.576 | 0.658 |

At 8 kHz, the measured sample receiver processes approximately **3.18× audio
speed with Perl and 2.94× with PDL** during tone search. With the tone supplied,
the figures are **30.70× and 36.55×**. At 16 kHz with search they fall to
**1.74× and 1.52×**, below the 5× target at 16 kHz. These measurements are for
macOS; Linux and Raspberry Pi throughput were not measured in this run.

### Complete WAV decoding

These calls also include in-memory WAV reading, PCM conversion and close:

| Workload | Perl time | PDL time |
| --- | ---: | ---: |
| 8 kHz, tone search | 2.906 s | 3.607 s |
| 8 kHz, known tone | 0.307 s | 0.264 s |
| 16 kHz, tone search | 5.376 s | 6.939 s |

### Generation

WAV generation includes PCM conversion.

| Sample rate | Samples, Perl | Samples, PDL | WAV, Perl | WAV, PDL |
| --- | ---: | ---: | ---: | ---: |
| 8 kHz | 0.042 s | 0.012 s | 0.076 s | 0.029 s |
| 16 kHz | 0.084 s | 0.021 s | 0.152 s | 0.056 s |

PDL accelerates generation in these cases. Its current tone-search reception
is slower than Perl in both sample-rate cases; known-tone reception is faster.
`perl` remains the default. `auto` selects PDL by availability and does not
benchmark or choose a backend by workload.

## Why PDL is only partly accelerated

The [current implementation](../lib/Ham/RTTY/_Internal/PDL.pm) uses PDL for tone
synthesis, PCM operations and filtered spectral projections. Acquisition
projections, guard/ring processing and biquad recurrences still run in Perl.
Each receiver batch copies filtered history windows into Perl arrays, builds
a PDL tensor and exports powers/energies back to arrays.

The batch cap is **128 hops**. A separate 16-hop experiment is excluded from
these results. Compiled PDL::PP filters, persistent feature storage and vectorized
acquisition have not been implemented or measured in the release.

## What the timers include

Sample generation includes generator construction and synthesis. Sample
reception includes detector construction, block feeds and finalization. WAV
operations include in-memory handles, library construction, conversion and
close. The WAV reader uses its default block size; `--block` controls direct
sample reception. Event preparation and preparation of the source audio are
outside the operation timers. Disk I/O, devices, Perl startup and module loading
are excluded. Memory use, 128-candidate searches and sustained long-recording
throughput were not measured.

Operations and backends run in a fixed order within one process, with a
prepared detector retained for snapshot measurements. Allocation history can
affect the timings. Raw output also includes analyzer rebuilds and batches of
100 cached snapshot reads; tiny or negative CPU deltas reflect timer precision.
Three calls are insufficient to estimate variance or percentile latency.

## Repeat the measurements

Run from the repository root in the same Perl environment:

```sh
perl maint/benchmark.pl --json --iterations 3
perl maint/benchmark.pl --json --iterations 3 --known-frequency
perl maint/benchmark.pl --json --iterations 3 --rate 16000
```

Preserve raw totals and record revision, environment, commands and input hashes.
Use wall time for the ratios above and state how averages are derived. Keep
timing runs separate from tests. `perl maint/benchmark.pl --help` describes
workload controls. `perl maint/benchmark-platforms.pl --help` describes the
separate CI rate protocol; its rates and these call means are not interchangeable.
Use `perl maint/reception-corpus.pl` to measure accuracy separately from speed.

## Earlier CI platform measurements, 2026-10-25

[Test run 40187441836](https://github.com/gipidevdor/ham-rtty/actions/runs/40187441836)
measured source `85eb8f3fce614d30cb53eaeb0da6b978dbc3dacc` on five configurations.
These are earlier measurements, not a fresh platform run of `c635a8a`. The
[raw platform results](platform-results.json) retain absolute rates, call counts,
elapsed times, Perl/PDL versions, artifact names and hashes. All use Perl 5.40
and PDL 2.106 except the minimum configuration, Perl 5.20 and PDL 2.081.
The runner labels identify the configured macOS ARM64 and Intel jobs; the raw
Perl architecture string alone does not distinguish those CPU families.

The message is `CQ CQ DE TESTCALL` at 8,000 Hz; receiver tone is searched.
Each operation is warmed once, then measured for at least one wall-clock second
with complete calls. Slow reception cases contain only one measured call.
PCM cases read/write one second of mono audio in memory at each bit depth;
they are raw PCM conversion, distinct from complete message generation/decoding.

Each ratio is PDL calls/second divided by Perl calls/second on the same runner.
Above 1 favours PDL; below 1 favours Perl. These are single shared-runner
observations, not stable platform rankings or processor comparisons.

| Operation | Linux | macOS ARM64 | macOS Intel | Windows | Linux minimum |
| --- | ---: | ---: | ---: | ---: | ---: |
| Generate samples | 3.57x | 3.70x | 3.37x | 2.81x | 3.56x |
| Receive, complete feed | 1.00x | 0.97x | 1.19x | 0.79x | 1.00x |
| Receive, 4,096-sample feeds | 0.91x | 0.71x | 0.99x | 0.79x | 0.83x |
| Read PCM WAV, 8-bit | 1.01x | 0.85x | 0.90x | 0.71x | 0.90x |
| Read PCM WAV, 16-bit | 1.15x | 1.07x | 1.21x | 0.81x | 1.01x |
| Read PCM WAV, 24-bit | 0.96x | 1.07x | 0.97x | 0.88x | 0.95x |
| Write PCM WAV, 8-bit | 1.41x | 1.34x | 1.39x | 1.31x | 1.34x |
| Write PCM WAV, 16-bit | 1.49x | 1.14x | 1.36x | 1.32x | 1.42x |
| Write PCM WAV, 24-bit | 1.33x | 1.32x | 1.34x | 1.20x | 1.28x |

PDL improves generation in these runs. Reception and PCM conversion vary by
platform and feed pattern. Compare absolute rates in the raw record and measure
your own workload before choosing a backend.

## Historical evidence

[Benchmark history](benchmark-history.md) retains earlier local observations.
[Earlier local raw results](benchmark-results.json),
[the 85eb8f3 timing and verification record](current-results.json) and
[earlier platform raw results](platform-history-results.json) belong to their
original sources. The current local record is [performance-results.json](performance-results.json).
The earlier CI table above remains explicitly tied to `85eb8f3`.
