# Measured performance

[Overview](../README.md) · [Task guide](usage.md) · [Examples](../examples/README.md) · [Verification](verification.md)

## Current local measurements, 2026-10-27

Measured source: `6b036001daed9cb5c1dae1dd301915638fc2d142`.
Environment: Apple M4, macOS 27.0.1 ARM64, Perl 5.44.0, PDL 2.106.
[Raw results](performance-results.json) include commands, sample counts,
CPU/wall totals, ratios and source hashes. These runs use the bounded receiver.

All cases generate `CQ CQ DE TESTCALL` at 45.45 baud, 2125 Hz MARK,
170 Hz shift and 1.5 stop bits: approximately **3.17 seconds of audio**, fed in
4,096-sample blocks. Search acquires one tone pair over the initial half second
on a 10 Hz grid; the known-tone case supplies the MARK and shift. Baud and
shift are configured in both cases. Times are the mean of three calls.
Workloads ran sequentially, without concurrent tests or coverage collection.

### Sample reception

`R` is processing seconds divided by audio seconds. Lower is better; `R < 1`
means this in-memory recording was processed faster than playback duration.
Its inverse, `1/R`, is audio seconds processed per wall second. Live capture
latency is excluded. Times and ratios in these tables use wall time.

| Workload | Perl time | PDL time | Perl R | PDL R |
| --- | ---: | ---: | ---: | ---: |
| 8 kHz, tone search | 0.2814 s | 0.1161 s | 0.0888 | 0.0366 |
| 8 kHz, known tones | 0.0572 s | 0.0856 s | 0.0181 | 0.0270 |
| 16 kHz, tone search | 0.5331 s | 0.1675 s | 0.1682 | 0.0528 |
| 16 kHz, known tones | 0.1095 s | 0.1096 s | 0.0346 | 0.0346 |

### Complete WAV decoding

These calls also include in-memory WAV reading, PCM conversion and close:

| Workload | Perl time | PDL time |
| --- | ---: | ---: |
| 8 kHz, tone search | 0.2833 s | 0.1161 s |
| 8 kHz, known tones | 0.0589 s | 0.0865 s |
| 16 kHz, tone search | 0.5366 s | 0.1742 s |
| 16 kHz, known tones | 0.1116 s | 0.1125 s |

### Generation

WAV generation includes PCM conversion. These rows use the corresponding
known-tone command; search commands repeat generation and retain their own totals.

| Sample rate | Samples, Perl | Samples, PDL | WAV, Perl | WAV, PDL |
| --- | ---: | ---: | ---: | ---: |
| 8 kHz | 0.0046 s | 0.0047 s | 0.0169 s | 0.0114 s |
| 16 kHz | 0.0086 s | 0.0070 s | 0.0327 s | 0.0199 s |

### What the timers include

Sample generation includes generator construction and synthesis. Sample
reception includes detector construction, block feeds and finalization. WAV
operations include in-memory handles, library construction, conversion and
close. The WAV reader uses its default block size; `--block` controls direct
sample reception. Event preparation and source audio preparation are outside
the operation timers. Disk I/O, devices, Perl startup and module loading are
excluded. RAM measurements below use a separate fresh-process protocol.

Operations and backends run in a fixed order within one process, with a
prepared detector retained for snapshot measurements. Allocation history can
affect timings. Raw output also includes analyzer rebuilds and batches of
100 cached snapshot reads; tiny CPU deltas reflect timer precision. Three calls
are insufficient to estimate variance or percentile latency. Synthetic speed
measurements do not establish field reception accuracy.

## CI platform measurements, 2026-10-27

[Test run 40524668493](https://github.com/gipidevdor/ham-rtty/actions/runs/40524668493)
measured source `084dbc682b3fc29714a0b9e8c0ffcab0424bc770` on five configurations.
This source already contains the bounded receiver; subsequent changes up to the
local measured revision only update documentation. The
[raw platform results](platform-results.json) retain absolute rates, call counts,
elapsed times, Perl/PDL versions, artifact names and SHA-256 digests.
The runner labels distinguish the configured macOS ARM64 and Intel jobs.

The message is `CQ CQ DE TESTCALL` at 8,000 Hz; receiver uses the default known 2125/2295-Hz tone pair.
Each operation is warmed once, then measured for at least one wall-clock second
with complete calls. PCM cases read/write one second of mono audio in memory
at each bit depth; they are raw PCM conversion, distinct from complete message
WAV generation/decoding. All use Perl 5.40 and PDL 2.106 except the minimum
configuration, Perl 5.20 and PDL 2.081; exact patch versions are in the raw data.

Each ratio is PDL calls/second divided by Perl calls/second on the same runner.
Above 1 favours PDL; below 1 favours Perl. These are single shared-runner
observations, not stable platform rankings or processor comparisons.

| Operation | Linux | macOS ARM64 | macOS Intel | Windows | Linux minimum |
| --- | ---: | ---: | ---: | ---: | ---: |
| Generate samples | 0.92x | 1.18x | 1.15x | 0.79x | 0.91x |
| Receive, complete feed | 0.59x | 0.77x | 0.79x | 0.36x | 0.51x |
| Receive, 4,096-sample feeds | 0.58x | 0.79x | 0.76x | 0.37x | 0.51x |
| Read PCM WAV, 8-bit | 0.96x | 0.97x | 1.00x | 0.80x | 1.02x |
| Read PCM WAV, 16-bit | 1.35x | 1.00x | 1.22x | 0.93x | 1.14x |
| Read PCM WAV, 24-bit | 1.07x | 0.97x | 1.82x | 1.00x | 1.08x |
| Write PCM WAV, 8-bit | 1.41x | 1.53x | 1.58x | 1.39x | 1.41x |
| Write PCM WAV, 16-bit | 1.48x | 1.61x | 1.75x | 1.45x | 1.48x |
| Write PCM WAV, 24-bit | 1.28x | 1.59x | 1.43x | 1.26x | 1.32x |

PDL performance varies by workload and feed pattern. Compare absolute rates in
the raw record and measure your own workload before choosing a backend.
`perl` remains the default; `auto` selects availability rather than speed.
The CI rate protocol and local call means are not interchangeable.

## Why PDL is only partly accelerated

PDL broadcasts the two projections together and accelerates synthesis and PCM. UART state, validation, run construction and acquisition control remain Perl. Small windows and conversion overhead limit acceleration; acquisition often dominates search. `auto` chooses availability only and is never a speed selector. These measurements describe this machine, not a universal speed advantage.

## Peak resident memory

Measured 2026-10-27 on Apple M4, 16 GiB RAM, macOS 27.0.1 ARM64,
Perl 5.44.0 and PDL 2.106, source revision `e55326fb2a3d835ce27387e64527f0e330ecc4d4`.
The [raw RAM results](memory-results.json) retain all 30 observations,
commands, input and source hashes, native timer output, decoded text,
warnings and module-loading checks. CPU timing tables above retain
their own source revision and protocol.

Each workload/backend has three fresh-process observations, run sequentially
with alternating backends. No tests or coverage collection ran alongside them.
The metric is macOS `/usr/bin/time -l` **maximum resident set size**, in bytes;
1 MiB is 1,048,576 bytes. The table shows the **median peak RSS**, followed by
minimum–maximum peak RSS. No baseline is subtracted.

| Workload | Perl, PDL unloaded (MiB) | PDL 2.106 (MiB) |
| --- | ---: | ---: |
| Loaded toolkit, no signal | 14.03 (14.03–14.05) | 20.69 (20.62–20.72) |
| WAV reception: 120 s, 48 kHz | 20.70 (20.70–20.75) | 27.55 (27.47–27.58) |
| DWD WAV reception: 30 s, 8 kHz | 16.84 (16.69–16.86) | 23.52 (23.48–23.61) |
| Streamed generation: 120 s, 48 kHz | 18.58 (18.50–18.59) | 26.89 (26.78–26.94) |
| Collected generation: 120 s, 48 kHz | 205.20 (205.17–205.20) | 213.52 (213.52–213.64) |

The whole-process peaks include the interpreter, module/native-library loading,
event preparation, working buffers, retained receiver history, results and
JSON diagnostics. The initialized-toolkit row constructs the facade without
processing audio. PDL is installed in this environment but remains unloaded
in every Perl observation; every PDL observation confirms it was loaded.
These are explicit `perl`/`pdl` choices, not `auto`.

The synthetic WAV contains exactly 5,760,000 samples: 120 seconds at 48000 Hz,
16-bit mono. It is created once outside the measured processes, and both
backends read the same hashed file. Generation compares `Generator->stream` and `Generator->generate` on the same
sampled events and duration, with 4096-sample internal blocks. The DWD file contains 240,000 samples
at 8000 Hz and uses its documented 50-baud, 1275-Hz MARK, 450-Hz shift settings.
All reception runs analyze every sample and return identical text across
backends and repetitions. Both input clips return one recorded warning;
the synthetic file deliberately ends inside a frame.

For the requested 120-second `read_wav` workload, the largest observed peaks
were **20.75 MiB for Perl** and **27.58 MiB for PDL**. PDL adds resident native
modules; it does not reduce the cost of retaining the public Perl sample
array. Streamed generation consumes and discards each block, while collected
generation retains all 5,760,000 values. This is why streaming has a much
smaller peak for that workload. WAV reception also streams PCM, while retaining
bounded decoder history; these measurements do not establish constant memory
for recordings of arbitrary length.

The earlier single-process **19.80 MiB** Perl observation is retained in
[the historical performance data](performance-history-results.json). The new paired
comparison uses the updated measurement helper and repeated fresh processes.
Linux/Windows RSS and other recording lengths remain unmeasured.

## Bounded reception and recommended defaults

The recommended default is **Perl with streamed I/O and 4096-sample blocks**.
Use `read_wav`, `write_wav` and `stream_samples` for file/block workflows.
`samples`, `wav_bytes`, `decode_wav_bytes` and collected Audio reads retain
whole arrays or byte strings by their documented contracts. Keep the frame,
run, byte and sample ceilings in place; increasing them is an explicit choice.
PDL remains optional, selected explicitly when its tradeoffs suit the workload.
`auto` continues to choose availability; it is not a memory policy.

The receiver now processes caller-sized arrays in bounded pieces, retains
only the initial half second for acquisition, and batches wide PDL projections
to at most 65,536 cells per matrix. Known-tone and smaller projections retain
the direct native path. WAV reception checks declared sample counts against
frame/run budgets before reading PCM. No samples are dropped or resampled;
public return types, snapshots and existing resource ceilings are preserved.

A separate paired experiment compares source `44e2799293e040020f903f54d75fc7bf1150dd67`
with `084dbc682b3fc29714a0b9e8c0ffcab0424bc770`, using the identical measurement helper,
input bytes and machine. Thirty sequential fresh processes provide three
observations per phase/case/backend. The following values are median peak
RSS in MiB; [raw optimization results](memory-optimization-results.json)
retain every range, timer output, command and source/input hash.

| Workload | Before (MiB) | Bounded implementation (MiB) |
| --- | ---: | ---: |
| 120 s WAV, Perl | 20.80 | 20.81 |
| 120 s WAV, PDL | 27.67 | 27.62 |
| 960,000-sample feed, Perl | 85.81 | 48.19 |
| 960,000-sample feed, PDL | 92.69 | 54.98 |
| 384 kHz / 20 baud wide search, PDL | 365.11 | 53.52 |

The ordinary WAV path remains around 20.8 MiB for Perl and 27.6 MiB for PDL.
The caller-sized feed uses about 44% less peak RSS with Perl and 41% less with
PDL. The PDL stress case uses about **85% less**: median 365.11 to 53.52 MiB,
with a largest observed bounded peak of 54.61 MiB. This stress input is a
supported edge configuration, not a representative radio recording.

The stress-case median process wall time increases from 2.42 to 3.45 seconds:
smaller native batches trade some throughput for a much smaller, predictable
working set. The standard 120-second WAV medians remain approximately
12.4 seconds for Perl and 7.8 seconds for PDL in this paired experiment.
These process timings include startup and use a different protocol from the
historical CPU-R tables. All analyzed sample counts and decoded text agree
before/after and between backends; memory reductions do not establish field
reception accuracy.

### Reproduce the stress inputs

Create `memory.wav` with the earlier command, outside measured processes.
This standalone Perl recipe writes the first 960,000 PCM frames to `feed-20s.wav`
in bounded blocks and creates `wide-search.wav` through the streaming WAV API.
Run it from the checkout in a directory where those two output paths are new:

```perl
use 5.020;
use strict;
use warnings;
use Ham::RTTY;
use Ham::RTTY::Audio;

my $audio = Ham::RTTY::Audio->new;
open my $input, '<:raw', 'memory.wav' or die $!;
my $reader = $audio->reader($input);
die 'Expected at least 20 seconds of 48000-Hz mono PCM16'
    unless $reader->{sample_rate} == 48000 && $reader->{channels} == 1
    && $reader->{bits} == 16 && $reader->{sample_count} >= 960000;
my $remaining = 960000;
$audio->write_blocks('feed-20s.wav', sub {
    return unless $remaining;
    my $block = $reader->{next}->() or die 'Input is shorter than 20 seconds';
    splice @{$block}, $remaining if @{$block} > $remaining;
    $remaining -= @{$block};
    return $block;
}, sample_rate => 48000, sample_count => 960000, bits => 16);
close $input or die $!;
Ham::RTTY->new(sample_rate => 384000, baud => 20)->write_wav('CQ', 'wide-search.wav');
```

Measure each command three times in a fresh process:

```sh
/usr/bin/time -l perl maint/memory.pl --feed feed-20s.wav --backend perl
/usr/bin/time -l perl maint/memory.pl --feed feed-20s.wav --backend pdl
/usr/bin/time -l perl maint/memory.pl --feed wide-search.wav --backend pdl --baud 20 --search --frequency-step 5
```

The `--feed` benchmark deliberately stages one caller-sized array and accepts
at most 1,000,000 samples. Normal file reception should use the streaming
`--read` workload instead. The source revisions and hashes in the raw report
identify the before/after implementations; earlier measurements remain historical.

## Repeat

```sh
perl maint/benchmark.pl --rate 8000 --block 4096 --iterations 3 --known-frequency --json
perl maint/benchmark.pl --rate 16000 --block 4096 --iterations 3 --known-frequency --json
perl maint/benchmark.pl --rate 8000 --block 4096 --iterations 3 --json
perl maint/benchmark.pl --rate 16000 --block 4096 --iterations 3 --json
perl maint/benchmark-platforms.pl --seconds 1 --json platform.json
perl maint/memory.pl --create memory.wav
/usr/bin/time -l perl maint/memory.pl --baseline --backend perl
/usr/bin/time -l perl maint/memory.pl --baseline --backend pdl
/usr/bin/time -l perl maint/memory.pl --read memory.wav --backend perl
/usr/bin/time -l perl maint/memory.pl --read memory.wav --backend pdl
/usr/bin/time -l perl maint/memory.pl --read corpus/free/dwd-france-day.wav --baud 50 --mark 1275 --shift 450 --backend perl
/usr/bin/time -l perl maint/memory.pl --read corpus/free/dwd-france-day.wav --baud 50 --mark 1275 --shift 450 --backend pdl
/usr/bin/time -l perl maint/memory.pl --stream --backend perl
/usr/bin/time -l perl maint/memory.pl --stream --backend pdl
/usr/bin/time -l perl maint/memory.pl --collect --backend perl
/usr/bin/time -l perl maint/memory.pl --collect --backend pdl
```

For RAM, run each measured command three times as separate processes, without
concurrent benchmarks, tests or coverage. Run the fixture-creation command only
once before measurement. `/usr/bin/time -l` above is the macOS interface; other
systems require their own RSS instrumentation. Read `perl maint/memory.pl --help`
for the supported workloads. The raw report also retains process wall/user/system
times; those include startup and follow a different protocol from the earlier
CPU timing tables.

## Historical evidence

[Earlier local raw results](performance-history-results.json) preserve the
measurements of source `3627c44989eff9ab9c9bbfa5fe409e348008dc85` unchanged.
The current local record is [performance-results.json](performance-results.json).
RAM records retain their own source revisions and protocols above.
