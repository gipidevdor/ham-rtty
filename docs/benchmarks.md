# Benchmarks

[Overview](../README.md) · [Verification](verification.md) · [CPU raw results](performance-results.json) · [RAM raw results](memory-results.json)

## Protocol

The CPU timing observations below were measured 2026-10-27 on Apple M4 / macOS ARM64, Perl 5.44.0, PDL 2.106; production revision `3627c44`. The RAM comparison has its own revision and protocol below.

Message `CQ CQ DE TESTCALL`, 45.45 baud, 2125 Hz MARK, +170 Hz SPACE, 1.5 stop bits. Three iterations, 4096-sample blocks, 8/16 kHz mono. R is processing seconds divided by audio seconds; smaller is faster. CPU uses Perl `times`; wall uses Time::HiRes. Each input is approximately 3.17 seconds. Generation, reception, WAV conversion and snapshot costs are separate. Reception excludes fixture generation. Timing workloads ran sequentially without tests or coverage collection. Raw results retain exact commands, counts, source hashes and timing totals.

## Streaming reception

| Rate | Tones | Perl CPU R | PDL CPU R | Perl wall R | PDL wall R |
| --- | --- | ---: | ---: | ---: | ---: |
| 8000 Hz | known | 0.0179 | 0.0263 | 0.0179 | 0.0267 |
| 8000 Hz | search | 0.0862 | 0.0357 | 0.0868 | 0.0364 |
| 16000 Hz | known | 0.0347 | 0.0336 | 0.0340 | 0.0337 |
| 16000 Hz | search | 0.1661 | 0.0526 | 0.1666 | 0.0525 |

Known tones are supplied explicitly; search acquires one pair over the first half second at the configured 170 Hz shift, using a 10 Hz grid. Baud is always configured; neither case estimates baud or shift. These are short synthetic workloads, not field reception accuracy measurements.

## Why PDL is only partly accelerated

PDL broadcasts the two projections together and accelerates synthesis and PCM. UART state, validation, run construction and acquisition control remain Perl. Small windows and conversion overhead limit acceleration; acquisition often dominates search. `auto` chooses availability only and is never a speed selector. These measurements describe this machine, not a universal speed advantage.

## Peak resident memory

Measured 2026-10-27 on Apple M4, 16 GiB RAM, macOS 27.0.1 ARM64,
Perl 5.44.0 and PDL 2.106, source revision `e55326fb2a3d835ce27387e64527f0e330ecc4d4`.
The [raw RAM results](memory-results.json) retain all 30 observations,
commands, input and source hashes, native timer output, decoded text,
warnings and module-loading checks. Earlier CPU timing tables above retain
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
[the historical performance data](performance-results.json). The new paired
comparison uses the updated measurement helper and repeated fresh processes.
Linux/Windows RSS and other recording lengths remain unmeasured.

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
