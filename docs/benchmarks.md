# Benchmarks

[Overview](../README.md) · [Verification](verification.md) · [Raw results](performance-results.json)

## Protocol

Measured 2026-10-27 on Apple M4 / macOS ARM64, Perl 5.44.0, PDL 2.106; production revision `3627c44`.

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

A fresh process receiving exactly 120 seconds at 48000 Hz (5,760,000 samples, 16-bit mono) through `read_wav` used **19.80 MiB peak RSS** (20,758,528 bytes). macOS `/usr/bin/time -l` measured resident memory; fixture creation ran separately. `maint/memory.pl` reproduces both steps. The receiver reports all 5,760,000 samples; the fixture deliberately ends inside a frame and therefore returns an incomplete-frame warning.

The RSS result covers this 120-second configuration. Larger history limits,
wider acquisition bands, collected sample arrays and PDL have different
memory costs. Linux and Windows RSS remain unmeasured.

## Repeat

```sh
perl maint/benchmark.pl --rate 8000 --block 4096 --iterations 3 --known-frequency --json
perl maint/benchmark.pl --rate 16000 --block 4096 --iterations 3 --known-frequency --json
perl maint/benchmark.pl --rate 8000 --block 4096 --iterations 3 --json
perl maint/benchmark.pl --rate 16000 --block 4096 --iterations 3 --json
perl maint/benchmark-platforms.pl --seconds 1 --json platform.json
perl maint/memory.pl --create memory.wav
/usr/bin/time -l perl maint/memory.pl --read memory.wav
```
