# Executable examples

[Documentation](../docs/README.md) · [Task guide](../docs/usage.md) · [Contributing](../CONTRIBUTING.md)

## First run

Run a tour of the API:

```sh
perl -Ilib examples/workflows.pl
```

List the examples, then run one:

```sh
perl -Ilib examples/run-all.pl --list
perl -Ilib examples/run-all.pl --only text-events
```

To run the full catalog:

```sh
perl -Ilib examples/run-all.pl --backend perl
```

Numerical examples accept `--backend perl`, `auto` or `pdl`. PDL requires
version 2.081 or later in the same Perl environment. `auto` uses PDL when
available; see [performance](../docs/benchmarks.md) for speed comparisons.

Individual numerical examples accept a positional backend:

```sh
perl -Ilib examples/pcm-streams.pl perl
perl -Ilib examples/reception-samples.pl pdl
```

The runner and the `send.pl`, `receive.pl` and `midi.pl` tools accept `--help`.

After installation, omit `-Ilib`. Keep the examples and bundled corpus together.

Each example runs independently, checks its result and cleans up its temporary
files. Real recordings are still missing; the dedicated
[corpus check](../corpus/README.md) fails until reviewed fixtures are admitted.

## Choose a path

| Example | Paths demonstrated | Backend argument |
| --- | --- | --- |
| [text-events.pl](text-events.pl) | ITA2 symbols, shift state, USOS, framed bits and incremental event decoding | None |
| [sample-streams.pl](sample-streams.pl) | Collected samples, streamed samples, progress, reset and independent iterators | perl / auto / pdl |
| [memory-files.pl](memory-files.pl) | WAV byte strings, borrowed handles, named paths and explicit replacement | perl / auto / pdl |
| [pcm-streams.pl](pcm-streams.pl) | PCM 8/16/24, callback and pull I/O, writer lifecycle and stereo selection | perl / auto / pdl |
| [reception-samples.pl](reception-samples.pl) | Configured tone and baud, incremental reception, silence and snapshots | perl / auto / pdl |
| [midi-paths.pl](midi-paths.pl) | Timed/sampled events to SMF bytes, handles and files, MIDI settings | None |
| [results.pl](results.pl) | Result construction, every accessor, independent copies and JSON | None |
| [failure-recovery.pl](failure-recovery.pl) | All library error families, failed replacement, recoverable validation and failed writers | perl / auto / pdl |
| [cli-paths.pl](cli-paths.pl) | All CLI commands, UTF-8 files/stdin, binary stdout and exit codes | perl / auto / pdl |
| [workflows.pl](workflows.pl) | Common end-to-end workflows with temporary files | None |

`reception-samples.pl` uses synthetic signals. Real-recording results are
reported separately by `maint/reception-corpus.pl` after fixture admission.
On Windows, prefer named binary files; see the [command manual](../bin/ham-rtty).

## Public API index

Find an example for each method below. The [JSON catalog](routes.json) is
also used by the tests. Option details are in the module POD.

| API | Methods/functions and example |
| --- | --- |
| Ham::RTTY | `new, encoder, decoder, encode, decode, events, sampled_events, decode_events, bits` → [text-events.pl](text-events.pl); `generator, samples, stream_samples` → [sample-streams.pl](sample-streams.pl); `wav_bytes, decode_wav_bytes, generate_wav, decode_wav, write_wav, read_wav` → [memory-files.pl](memory-files.pl); `detector, decode_samples` → [reception-samples.pl](reception-samples.pl); `midi_bytes, generate_midi, write_midi` → [midi-paths.pl](midi-paths.pl) |
| Ham::RTTY::Encoder | `new, validate, encode, events, frames, bits, result` → [text-events.pl](text-events.pl) |
| Ham::RTTY::Decoder | `new, decode, feed, result, finish, reset, state, decode_bits` → [text-events.pl](text-events.pl) |
| Ham::RTTY::Events | `validate_events, to_samples, to_timed` → [text-events.pl](text-events.pl) |
| Ham::RTTY::Baudot | `new, tables, character, reset` → [text-events.pl](text-events.pl) |
| Ham::RTTY::Generator | `new, validate, generate, stream, result, state, reset` → [sample-streams.pl](sample-streams.pl) |
| Ham::RTTY::Audio | `new, read_file, write_file, read_blocks, write_blocks, reader, read, writer, write` → [pcm-streams.pl](pcm-streams.pl) |
| WAV writer | `feed, result, finish, state` → [pcm-streams.pl](pcm-streams.pl) |
| Ham::RTTY::Detector | `new, feed, result, finish, state, reset` → [reception-samples.pl](reception-samples.pl) |
| Ham::RTTY::MIDI | `new, encode, write, write_file` → [midi-paths.pl](midi-paths.pl) |
| Ham::RTTY::Result | `new, text, notation, frequency, baud, events, warnings, diagnostics, complete, has_text, has_warnings, as_hash` → [results.pl](results.pl) |
| Ham::RTTY::Error | `new, throw, code, message, context, as_string` → [failure-recovery.pl](failure-recovery.pl) |

## File tools

```sh
perl -Ilib examples/send.pl --baud 50 --mark 650 practice.wav "CQ DE TESTCALL"
perl -Ilib examples/receive.pl --mark 650 --baud 50 --json practice.wav
perl -Ilib examples/midi.pl practice.mid "CQ DE TESTCALL"
```

Add `--overwrite` to replace an existing destination.

## Automated verification

`prove -lv t/29-examples.t` runs the catalog in isolated directories with
warnings fatal and every available backend. It checks results and coverage of
public methods, including WAV writers. CI runs it on Linux, macOS and Windows.

The archive installation check runs the complete catalog again against the
installed library. See [contributing](../CONTRIBUTING.md) and the
[release procedure](../docs/releasing.md) for author checks, coverage, security
audits, benchmarks and corpus maintenance commands.
