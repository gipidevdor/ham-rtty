# Task guide

[Overview](../README.md) · [Examples](../examples/README.md) · [Contributing](../CONTRIBUTING.md)

[Commands](#command-line-use) · [Library](#library-recipes) ·
[Installation](installing.md) · [Recovery](#when-you-need-help) ·
[Limits](#practical-limits)

## Requirements and installation

Requires Perl 5.20 or later; see [installation](installing.md).
From a checkout, run commands as `perl -Ilib bin/ham-rtty`.

## Command-line use

`ham-rtty` uses the same API and defaults as the Perl library.

| Task | Command |
| --- | --- |
| Text to ITA2 codes | `ham-rtty encode "CQ TEST"` |
| ITA2 codes to text | `ham-rtty decode "[LTRS] 01001 00001"` |
| Timed events as JSON | `ham-rtty events "SOS"` |
| Sampled events as JSON | `ham-rtty events --sample-rate 8000 "SOS"` |
| WAV practice file | `ham-rtty wav --baud 50 --stop-bits 1.5 --output practice.wav "CQ TEST"` |
| MIDI file | `ham-rtty midi --mark-note 77 --space-note 79 --output practice.mid "CQ TEST"` |
| Read a recording | `ham-rtty receive recording.wav` |
| Receive with hints | `ham-rtty receive --mark 650 --baud 50 recording.wav` |
| Machine-readable reception | `ham-rtty receive --json recording.wav` |
| Fail on reception warnings | `ham-rtty receive --strict recording.wav` |

Use `--input FILE` for UTF-8 text files or omit positional text to read stdin.
WAV input from stdin is spooled to a temporary file, subject to `--max-bytes`.
Use `--output FILE` for text, JSON, WAV or MIDI output, and `--overwrite` to
replace an existing file. Failed replacements preserve the old file.
`--output -` selects binary stdout.
Named binary files avoid shell-specific redirection behavior on Windows.
Options are case-sensitive, unabbreviated and may appear before or after
positional arguments; repeats are errors. Use `--` before dash-leading text.
Quote shell metacharacters and shift markers; the examples use double quotes.

Exit codes are 0 for success, 1 for empty reception or strict warnings,
2 for invalid usage/options, 3 for invalid data, resource limits or I/O errors,
and 4 for an unexpected internal failure. Text warnings and errors use stderr;
receive JSON includes its warnings. `--strict` preserves partial text and
returns status 1 when warnings occur. Use `--help` or `ham-rtty help COMMAND`
for command help, and `--version` for the installed version.
With `--lenient`, every text-encoding command reports substitutions on stderr,
including WAV, MIDI and events. Binary and JSON output contain only their
requested data.
Text input is limited to 8192 bytes by default; `--max-input-bytes` raises it
to at most 1048576.

## When you need help

`ham-rtty help COMMAND` lists options, defaults and an example.

| What you see | Next action |
| --- | --- |
| An option is rejected | Open help for that command. Use full, case-sensitive option names. |
| Text beginning with a dash is parsed as an option | Add `--` before the text argument. |
| An output file already exists | Choose a new path, or add `--overwrite` for deliberate replacement. |
| WAV or MIDI output is missing | Supply `--output practice.wav` or `--output practice.mid`. |
| A character is rejected | Check the [symbol policy](#symbol-policy) and selected ITA2 variant. |
| No text, partial text or reception warnings | Use `--json` to inspect the result. Supply matching `--mark`, `--shift` and `--baud`; check `--reverse`. |
| Stereo reception is unexpectedly weak | Try `--stereo left` or `--stereo right`; mixing can cancel opposite-phase audio. |
| PDL is unavailable | Use `--backend perl`, or install PDL in the same Perl environment. |
| PDL does not improve speed | Compare your operation and hints with the [measured workloads](benchmarks.md). `auto` selects availability. |
| A resource limit is reached | Check recording length and the [retained-history limits](#practical-limits) before raising the corresponding limit explicitly. |

Check tone, speed and input channel before adjusting detection thresholds.

## Library recipes

Each Perl block below is a standalone script. Run it with
`perl -Ilib your-script.pl` from a checkout, or `perl your-script.pl` after
installation. For the full API, use `perldoc Ham::RTTY`.

## Choose the data representation

| Representation | Meaning | Example |
| --- | --- | --- |
| Text | Perl character string | `'SOS'` |
| ITA2 codes | Five-bit numeric codes and shift markers | `'[LTRS] 00011'` |
| Timed events | MARK/SPACE integer microseconds | `{unit => 'us', segments => [...]}` |
| Sampled events | MARK/SPACE integer sample counts at one rate | `{sample_rate => 8000, segments => [...]}` |
| Samples | Mono numbers in [-1,1]; no embedded rate | `[0, 0.1, -0.1]` |
| WAV/MIDI bytes | A complete binary file in a scalar | Returned by `wav_bytes` / `midi_bytes` |
| Result | Decoded text plus events, warnings and diagnostics | Returned by reception methods |

External text bytes must be decoded to characters first. `use utf8` enables
non-ASCII literals in Perl source; it does not decode files automatically.
Binary WAV/MIDI output must not pass through a text encoding. For text output
containing accented/replacement characters, configure the output encoding,
for example `binmode STDOUT, ':encoding(UTF-8)'`.

## Text and timing

```perl
use strict;
use warnings;
use Ham::RTTY;
my $rtty = Ham::RTTY->new(baud => 50, stop_bits => 1.5);
my $notation = $rtty->encode('cq 123');
print $notation, "\n";
print $rtty->decode($notation), "\n";
my $events = $rtty->events('CQ 123');
print $rtty->decode_events($events, baud => 50)->text, "\n";
```

Notation contains numeric five-bit codes, most significant digit first, and
`[FIGS]`/`[LTRS]` markers. The `bits` method instead returns transmitted order:
start 0, five LSB-first data bits, stop 1. A 1.5-bit stop rounds up to two digits
in logical strings; use frames or events for exact duration.

ITA2 follows [ITU-T S.1](https://www.itu.int/rec/T-REC-S.1-199303-I/en).
ASCII lowercase is uppercased. Unsupported characters raise `RTTY_E_SYMBOL`;
`lenient => 1` substitutes `?`, with `RTTY_W_SYMBOL` in the Encoder Result.
No transliteration is applied. CR, LF, BELL, NULL and WRU use U+000D, U+000A,
U+0007, U+0000 and U+0005 respectively. Reserved national combinations are
unassigned in the ITU table. The US table differs in FIGS as follows:

| Letter position | ITU | US |
| --- | --- | --- |
| D | WRU | $ |
| F | reserved | ! |
| G | reserved | & |
| H | reserved | # |
| J | BELL | apostrophe |
| S | apostrophe | BELL |
| V | = | ; |
| Z | + | double quote |

USOS defaults on at both transmitter and receiver: SPACE returns the receiver
to LTRS; the encoder sends FIGS again when subsequent figures need it.
Set `usos => 0` on both ends for persistent shift state.

## Practice recordings and files

This recipe creates files in a temporary directory, so it can be run repeatedly.

```perl
use strict;
use warnings;
use File::Temp qw(tempdir);
use File::Spec;
use Ham::RTTY;

my $directory = tempdir(CLEANUP => 1);
my $wav = File::Spec->catfile($directory, 'practice.wav');
my $midi = File::Spec->catfile($directory, 'practice.mid');
my $rtty = Ham::RTTY->new(baud => 50, mark => 650, shift => 450);
$rtty->write_wav('CQ TEST', $wav, bits => 24);
$rtty->write_midi('CQ TEST', $midi, mark_note => 77, space_note => 79, program => 80);
my $result = $rtty->read_wav($wav, mark => 650, shift => 450, baud => 50);
print $result->text, "\n";
for my $warning (@{$result->warnings}) {
    warn "$warning->{code}: $warning->{message}\n";
}
```

Generation defaults to 45.45 baud. Supply reception settings separately from
the constructor's generation settings. WAV files provide their sample rate in
the header; MIDI uses channels 1–16 and programs 0–127.

Parent directories must exist. To replace a file, pass `overwrite => 1`:
output is written to a temporary sibling and renamed after a successful close.
Failed generation preserves the old file. Permission bits are preserved;
ownership, ACLs and other hard links are not transferred. Detected symlinks are
rejected, but the directory must also be protected from concurrent writers.
See the [file reference](../lib/Ham/RTTY.pm) for cleanup and replacement details.

Per-call options leave the object's defaults unchanged.

## Samples, streaming and incremental reception

```perl
use strict;
use warnings;
use Ham::RTTY;

my $rtty = Ham::RTTY->new(sample_rate => 8000, mark => 650, baud => 50);
my $next = $rtty->stream_samples('SOS', block_size => 1024);
my $detector = $rtty->detector(mark => 650, baud => 50);
my $blocks = 0;
while (my $block = $next->()) {
    $detector->feed($block);
    if (++$blocks % 8 == 0) {  # About once per second for this block size/rate.
        my $preview = $detector->result;
        # Cumulative preview: do not append it as a delta.
    }
}
my $final = $detector->finish;
print $final->text, "\n";
$detector->reset;

my $samples = $rtty->samples('SOS');
my $collected = $rtty->decode_samples($samples, mark => 650, sample_rate => 8000, baud => 50);
print $collected->text, "\n";
```

The iterator yields sample arrays, then `undef`. The detector rate must match
the array's actual rate; raw arrays carry no rate metadata. The factory inherits
sample rate/backend, but not generation tone or speed. Configure baud and tones
to match the sender; optional search estimates the pair at the configured shift.
Each facade stream owns an independent generator; changing block boundaries
does not change its waveform within one backend.

`finish` is idempotent. Call `reset` before feeding more data; validation
failures preserve history. Previews can revise earlier text as audio arrives.
Unchanged detector snapshots are cached. A fresh preview processes the retained
decision history; request previews periodically, rather than after every block.
Snapshots survive a reset. `Generator->stream` requires a READY object;
resetting that generator invalidates its old iterators.

Streaming reduces buffer size. Retained detector history is still bounded;
see [resource limits](#practical-limits).

## Custom events and MIDI export

```perl
use strict;
use warnings;
use Ham::RTTY;
use Ham::RTTY::Events qw(validate_events to_samples to_timed);
use Ham::RTTY::MIDI;

my $rtty = Ham::RTTY->new(baud => 50);
my $timed = $rtty->events('SOS');
my $sampled = to_samples($timed, 8000);
my $again = to_timed($sampled);
print validate_events($again), "\n";  # duration
my $decoder = $rtty->decoder(baud => 50);
$decoder->feed($sampled);
print $decoder->finish->text, "\n";
my $samples = $rtty->generator(sample_rate => 8000)->generate($sampled);
my $midi_bytes = Ham::RTTY::MIDI->new(mark_note => 77, space_note => 79)->encode($timed);
print length($midi_bytes), " MIDI bytes\n";
```

Timed events use `unit => 'us'` and positive integer `duration` fields;
sampled events use `sample_rate` and positive integer `samples` fields.
Runs alternate `state => 'mark'` and `state => 'space'`. Empty sequences and
leading/trailing MARK runs are valid. Across event-decoder feeds, equal states
at a block boundary are merged. Within each block, states must alternate.

Conversions round cumulative boundaries, avoiding per-segment drift. They
return fresh hashes but a round trip can lose resolution. Zero-length converted
runs are rejected; choose a higher rate or longer events. Sampled events must
match a generator's rate. Converting event units does not resample audio.

## Raw WAV processing and caller-owned handles

```perl
use strict;
use warnings;
use File::Temp qw(tempdir);
use File::Spec;
use Ham::RTTY;
use Ham::RTTY::Audio;

my $directory = tempdir(CLEANUP => 1);
my $path = File::Spec->catfile($directory, 'raw.wav');
my $rtty = Ham::RTTY->new(sample_rate => 8000);
my $audio = Ham::RTTY::Audio->new(block_samples => 1024);
my $samples = $rtty->samples('SOS');
my $next = $rtty->stream_samples('SOS', block_size => 1024);
$audio->write_blocks($path, $next,
    sample_rate => 8000, sample_count => scalar(@{$samples}), bits => 16);
my $metadata = $audio->read_blocks($path, sub {
    my ($block, $info) = @_;
    # Process normalized mono samples using $info->{sample_rate}.
});
print "$metadata->{sample_count} frames\n";
open my $in, '<:raw', $path or die $!;
my $recording = $audio->read($in);
close $in or die $!;
print scalar(@{$recording->{samples}}), " samples\n";
```

Audio methods do not decode RTTY. Input supports seekable mono/stereo PCM
8/16/24-bit WAV. Stereo selection is `left`, `right` or default `mix`; mixing
opposite-phase signals can cancel them. Output is mono. Unsupported formats
include float/compressed/extensible WAV and placeholder streaming lengths.
Trailing bytes outside RIFF produce a metadata warning. Collecting readers
return a full sample array; block readers call your callback and return metadata.

`Audio->writer($handle, sample_count => ...)` returns a writer with `feed`,
`result`, `state` and `finish`. It requires the exact total count for the WAV
header. A failed writer has no reset: discard it and its partial output.
`Audio->reader($handle)` returns a hash with a `next` code reference for manual
pull reading. Keep caller-owned handles open while iterating and close them
yourself. Reading rewinds seekable input to zero. Output handles need not seek.

Path methods own and close handles. Callback exceptions also close owned
handles before propagating. Direct handle methods leave them open even on
failure. Opening output with `>:raw` truncates existing content immediately;
use path methods when existing-file protection is needed.

## Binary data and structured failures

```perl
use strict;
use warnings;
use Ham::RTTY;

my $rtty = Ham::RTTY->new(baud => 50);
my $wav = $rtty->wav_bytes('SOS');
my $result = $rtty->decode_wav_bytes($wav, baud => 50);
print $result->text, "\n";
for my $warning (@{$result->warnings}) {
    warn "$warning->{code}: $warning->{message}\n";
}
my $all_fields = $result->as_hash;
my $midi = $rtty->midi_bytes('SOS');

my $ok = eval { $rtty->encode('CQ!'); 1 };
if (!$ok) {
    my $error = $@;
    if (ref($error) && $error->isa('Ham::RTTY::Error')) {
        warn $error->code . ': ' . $error->message . "\n";
    }
    else { die $error; }
}
```

Byte methods hold the complete file in memory; use file or block methods for
large recordings. Capture `$@` immediately after `eval` and branch on the
error's `code`. See the [error reference](../lib/Ham/RTTY/Error.pm).

Results are cumulative snapshots. `has_text` tests presence; `complete` marks
finalization. Check `warnings` before using the text. Arrays and hashes returned
by accessors are copies, and diagnostic fields may be absent. See
[Result](../lib/Ham/RTTY/Result.pm) for fields and warning codes.

## Option routing and next steps

The constructor stores encoding/generation defaults only. Per-call WAV generation
also accepts `bits`, `max_bytes` and `block_size`; MIDI export accepts its separate
note/program/tempo options. `overwrite` belongs only to path-writing helpers.
Decoder options belong on event/text decoding; detector options belong on audio
reception. WAV reception adds `stereo`, `max_bytes` and `block_samples`, taking
its sample rate from the header. Unknown or duplicate option names are errors.

`block_size` means generated samples per block; `block_samples` means reader
frames per block. Rates and frequencies are Hz; baud controls bit duration and stop lengths
are measured in bits. The module POD lists each option's range and default.

`backend => 'perl'` needs only core Perl. `pdl` requires PDL 2.081 or later;
`auto` chooses PDL by availability, not speed. Small blocks can favor Perl.
See [measurements](benchmarks.md) and [architecture](architecture.md).

Run `perl -Ilib examples/workflows.pl` for a tour of the API.
The [example catalog](../examples/README.md) covers individual methods.

## Reception settings

Reception handles one station. Configure baud, shift and polarity explicitly;
`search => 1` can acquire the tone pair within a band at the configured shift.
There is no automatic baud/shift identification, equalisation or diversity.
See the [Detector POD](../lib/Ham/RTTY/Detector.pm) for options and limits.

## Complete runnable scenarios

The [example catalog](../examples/README.md) covers PCM, streaming, reception,
results, errors and CLI use. Select an example with
`perl -Ilib examples/run-all.pl --only pcm-streams --backend auto`.

## Save and receive files

See the [practice-file recipe](#practice-recordings-and-files) for WAV and MIDI
output and WAV reception. Path methods open and close their own handles.

`write_wav` returns a statistics hash containing `state` and `samples`;
`write_midi` returns its byte count. `read_wav` returns a `Ham::RTTY::Result`.

## Symbol policy

The default repertoire follows [ITU-T S.1](https://www.itu.int/rec/T-REC-S.1-199303-I/en),
including LTRS/FIGS, SPACE, CR, LF, BELL, WRU and NULL. National figures F/G/H
remain unassigned in `ita2`. The `us` profile has its own figures table.
ASCII lowercase becomes uppercase; unsupported text raises `RTTY_E_SYMBOL`.
`lenient => 1` substitutes `?` with an encoding warning.
See [Text and timing](#text-and-timing) and
[Encoder POD](../lib/Ham/RTTY/Encoder.pm) for the complete rules.

## Speed, framing and reception

One bit lasts `1 / baud` seconds. Standard rates include 45.45, 50, 56.25, 75,
100 and 110 baud; the accepted range is 20..300. A frame contains one SPACE
start, five LSB-first data bits and MARK stop. Stops may be 1, 1.5 or 2 bits.
Idle is continuous MARK. Generation defaults to 2125 Hz MARK and 2295 Hz SPACE;
`reverse => 1` exchanges the tones. Phase remains continuous at transitions.

Constructor speed and tone configure **generation**. Supply known `mark`,
`shift` and `baud` on receiving calls separately. WAV input supplies its own
sample rate; raw sample input requires the actual rate. Measured bit period
is a Result diagnostic, not an automatic speed mode. USOS is configurable at
both ends; see [Text and timing](#text-and-timing).

Invalid arguments, I/O failures and resource errors throw `Ham::RTTY::Error`.
Uncertain reception produces [Result warnings](../lib/Ham/RTTY/Result.pm).

## Choose an interface

| Task | Interface | Reference |
| --- | --- | --- |
| Ordinary text, samples and files | `Ham::RTTY` convenience methods | [POD](../lib/Ham/RTTY.pm) |
| ITA2 codes and framed events | `Ham::RTTY::Encoder` | [POD](../lib/Ham/RTTY/Encoder.pm) |
| Strict notation or incremental events | `Ham::RTTY::Decoder` | [POD](../lib/Ham/RTTY/Decoder.pm) |
| Event validation and unit conversion | `Ham::RTTY::Events` | [POD](../lib/Ham/RTTY/Events.pm) |
| Tone generation from custom events | `Ham::RTTY::Generator` | [POD](../lib/Ham/RTTY/Generator.pm) |
| Incremental sample reception | `Ham::RTTY::Detector` | [POD](../lib/Ham/RTTY/Detector.pm) |
| Raw PCM WAV without RTTY decoding | `Ham::RTTY::Audio` | [POD](../lib/Ham/RTTY/Audio.pm) |
| MIDI export from custom events | `Ham::RTTY::MIDI` | [POD](../lib/Ham/RTTY/MIDI.pm) |
| Snapshots and exceptions | `Ham::RTTY::Result`, `Ham::RTTY::Error` | [Results](../lib/Ham/RTTY/Result.pm), [errors](../lib/Ham/RTTY/Error.pm) |

Read a module's manual with `perldoc`, for example `perldoc Ham::RTTY::Audio`.

## Optional PDL backend

Install PDL 2.081 or later into the Perl environment running your application,
then select `backend => 'pdl'` in the constructor or supported operation.
`backend => 'perl'` is the default. `backend => 'auto'` selects PDL when loadable,
otherwise Perl; it does not benchmark the workload. PDL needs a compatible
native build. Its benefit depends on operation, sample rate, tone hints and
buffer allocation. Acquisition control, UART state and run construction still run in Perl;
PDL accelerates the two-tone projections, synthesis and PCM conversion. See
[measured timings](benchmarks.md) for comparisons.

Both backends use the same public arrays and file/event formats. Floating-point
values can differ slightly, including one PCM unit near a rounding boundary.
Use `perl maint/benchmark.pl --help` and `perl maint/benchmark-platforms.pl --help`
to measure your own workload.

## Memory-conscious operation

Use the default `backend => 'perl'` with `read_wav`, `write_wav` and
`stream_samples` to keep whole PCM arrays out of file/block workflows.
The receiver handles large supplied blocks in bounded pieces and keeps only
the first half second for tone acquisition. Optional PDL searches also bound
their transient projection matrices. File reception rejects declared history
budgets before reading PCM data. Existing byte/frame/run/sample ceilings remain
in force; public collected-array and byte-string methods retain their documented
behavior. See the [paired RAM measurements](benchmarks.md#bounded-reception-and-recommended-defaults)
for the observed costs and throughput tradeoff.

## Practical limits

WAV input supports mono/stereo PCM 8/16/24-bit; output is mono. Stereo `mix`
averages channels and may cancel opposite-phase audio; `left` or `right` selects
one. Compressed, float, extensible WAV and unknown-length streaming headers
are unsupported. MIDI output is standard file type 0.

Generation defaults to 10,000,000 total samples. Audio detection defaults to
200,000 frames and 100,000 segments; its conservative preflight bounds hop
count using both limits. Event decoding defaults to 100,000 retained runs.
Increase `max_samples`, `max_frames` or `max_segments` explicitly when
appropriate. Streaming reduces block-buffer size but does not remove these
history limits. Every option's range and applicable method are specified in POD.

Reception compares two narrowband tone energies over approximately 0.65-bit
windows at about 12 hops per bit. ATC corrects unequal tracked tone peaks;
search acquires one pair at the configured shift. Both paths feed the same
UART synchroniser. Fading, interference and incorrect parameters can produce
wrong, partial or empty text. Review each Result's warnings. The
[verification record](verification.md) reports the tested conditions and
missing real-recording evidence. Run `perl maint/reception-corpus.pl` to check
fixture admission and measured CER; missing fixtures fail the command.

## Audio

See [Practice recordings and files](#practice-recordings-and-files) for a WAV
and MIDI round trip. [Custom events](#custom-events-and-midi-export) describes
exact fractional stop timing.

## Streaming

See [Samples, streaming and incremental reception](#samples-streaming-and-incremental-reception)
for the pull iterator and receiver lifecycle.

## Files and command line

See [Command-line use](#command-line-use) and
[Save and receive files](#save-and-receive-files) for input, output and file
protection. MIDI is a two-note visual/debug rendering.
