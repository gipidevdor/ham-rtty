# Free reception examples

[Corpus overview](../README.md) · [Credits and licences](LICENSES.md) ·
[Machine-readable inventory](../free.json)

Five small PCM WAV files can be tested offline. Four contain real radio
reception; one is an externally generated interoperability example.
The library needs no audio conversion program to read these distributed WAVs.

```sh
perl -Ilib bin/ham-rtty receive --baud 50 --mark 1275 --shift 450 corpus/free/dwd-france-day.wav
perl -Ilib bin/ham-rtty receive --baud 45.45 --mark 1470 --shift 170 corpus/free/amateur-contest.wav
perl -Ilib bin/ham-rtty receive --baud 45.45 --mark 915 --shift 170 corpus/free/wikipedia-generated.wav
perl maint/external-reception.pl --backend perl
```

Use `--json` on receive commands to inspect text, warnings and diagnostics.
The report command runs all five files and checks their recorded regression
budgets. Use `--backend pdl` for the optional numerical backend.

## What the results mean

The reference output comes from minimodem 0.24, independently of Ham::RTTY.
For comparison only, CRLF and bare CR become LF; other characters, including
spaces and controls, are retained. Disagreement is Levenshtein distance divided
by the independent output length. It is **not a verified character error rate**:
minimodem can also make errors, and the off-air transcripts are not manually
verified. The inventory preserves its raw output instead of inventing clean text.

| Example | Baud / shift | Recorded disagreement | Licence |
| --- | --- | --- | --- |
| [DWD France, daytime](dwd-france-day.wav) | 50 / 450 Hz | 5.23% | CC BY 4.0 |
| [DWD France, afternoon](dwd-france-afternoon.wav) | 50 / 450 Hz | 4.07% | CC BY 4.0 |
| [DWD UK, morning](dwd-uk-morning.wav) | 50 / 450 Hz | 11.86% | CC BY 4.0 |
| [Amateur contest](amateur-contest.wav) | 45.45 / 170 Hz | 20.00% | CC0 1.0 |
| [Wikipedia, generated](wikipedia-generated.wav) | 45.45 / 170 Hz | 0.00% | Public-domain dedication |

Baud and tone values above are the tested decoder settings, not independent
calibration of the transmitting equipment. The DWD clips contain station IDs,
frequency announcements and RY test sequences, rather than full forecasts.

These observations were measured on 2026-10-27 with source revision `74cd1b1`;
production modules were unchanged when adding the fixtures. Off-air regression
budgets allow one additional character of disagreement; the generated example
requires an exact match after the stated line-ending conversion. Improving
agreement passes the same checks. Warnings remain part of the report.

## Selection and limits

The DWD excerpts come from three distinct captures, not three crops of one
recording. The amateur excerpt comes from the start of a separate contest
recording. They were selected after inspecting independent decoded text and
spectrum; they are useful examples, not a random or representative radio survey.
Freesound previews are lossy sources and this is recorded in their provenance.

Other recordings were considered: benj500's CC0 RTTY sample and
Fringer_Cat's CC BY 4.0 sample lacked an established readable transcript in
this review; two other licensed DWD captures also decoded poorly. They are not
passed off as successful receptions or given invented reference text.

The four independently annotated release fixtures remain separate in
[real.json](../real.json). Run `perl maint/reception-corpus.pl` for that stricter
gate; adding these exploratory examples does not waive it.
