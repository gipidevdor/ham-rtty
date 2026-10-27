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
| Text to Morse | `ham-rtty encode "CQ TEST"` |
| Morse to text | `ham-rtty decode -- "-.. ."` |
| Timed events as JSON | `ham-rtty events "SOS"` |
| Sampled events as JSON | `ham-rtty events --sample-rate 8000 "SOS"` |
| WAV practice file | `ham-rtty wav --wpm 20 --effective-wpm 12 --output practice.wav "CQ TEST"` |
| MIDI file | `ham-rtty midi --note 77 --output practice.mid "CQ TEST"` |
| Read a recording | `ham-rtty receive recording.wav` |
| Receive with hints | `ham-rtty receive --frequency 650 --wpm 20 recording.wav` |
| Machine-readable reception | `ham-rtty receive --json recording.wav` |
| Fail on reception warnings | `ham-rtty receive --strict recording.wav` |

Use `--input FILE` for UTF-8 text files or omit positional text to read stdin.
WAV input from stdin is spooled to a temporary file, subject to `--max-bytes`.
Use `--output FILE` for text, JSON, WAV or MIDI output, and `--overwrite` to
replace an existing file. Failed replacements preserve the old file.
`--output -` selects binary stdout.
Named binary files avoid shell-specific redirection behavior on Windows.
Options are case-sensitive, unabbreviated and may appear before or after
positional arguments; repeats are errors. Use `--` before dash-leading Morse.
Quote shell metacharacters and prosigns; the examples use double quotes.

Exit codes are 0 for success, 1 for empty reception or strict warnings,
2 for invalid usage/options, 3 for invalid data, resource limits or I/O errors,
and 4 for an unexpected internal failure. Text warnings and errors use stderr;
receive JSON includes its warnings. `--strict` preserves partial text and
returns status 1 when warnings occur. Use `--help` or `ham-rtty help COMMAND`
for command help, and `--version` for the installed version.
Text input is limited to 8192 bytes by default; `--max-input-bytes` raises it
to at most 1048576.

## When you need help

`ham-rtty help COMMAND` lists options, defaults and an example.

| What you see | Next action |
| --- | --- |
| An option is rejected | Open help for that command. Use full, case-sensitive option names. |
| Morse beginning with a dash is parsed as an option | Add `--`: `ham-rtty decode -- "-.. ."`. |
| An output file already exists | Choose a new path, or add `--overwrite` for deliberate replacement. |
| WAV or MIDI output is missing | Supply `--output practice.wav` or `--output practice.mid`. |
| A character or prosign is rejected | Check the [symbol policy](#symbol-policy); quote tokens such as `"<AR>"`. |
| No text, partial text or reception warnings | Use `--json` to inspect the result. Supply known `--frequency` and `--wpm`; include `--effective-wpm` for Farnsworth spacing. |
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
| Morse | Dot/dash groups; spaces for letters, `/` for words | `'... --- ...'` |
| Timed events | ON/OFF integer microseconds | `{unit => 'us', segments => [...]}` |
| Sampled events | ON/OFF integer sample counts at one rate | `{sample_rate => 8000, segments => [...]}` |
| Samples | Mono numbers in [-1,1]; no embedded rate | `[0, 0.1, -0.1]` |
| WAV/MIDI bytes | A complete binary file in a scalar | Returned by `wav_bytes` / `midi_bytes` |
| Result | Decoded text plus events, warnings and diagnostics | Returned by reception methods |

External text bytes must be decoded to characters first. `use utf8` enables
non-ASCII literals in Perl source; it does not decode files automatically.
Binary WAV/MIDI output must not pass through a text encoding. For text output
containing accented/replacement characters, configure the output encoding,
for example `binmode STDOUT, ':encoding(UTF-8)'`.

## Text and prosigns

```perl
use strict;
use warnings;
use Ham::RTTY;

my $cw = Ham::RTTY->new;
print $cw->encode('CQ <AR>'), "\n";
print $cw->decode('... --- ... / - . ... -'), "\n";  # SOS TEST
print $cw->decode('.-.-.', prefer_prosigns => 1), "\n";  # <AR>
print $cw->encode('CQ!', unknown => 'skip'), "\n";
```

`<AR>` is one operational signal (prosign); `AR` is two letters. Shared
waveforms lose the original spelling, so decoding uses the documented
punctuation/prosign preference. The encoder supports A–Z, digits, accented E,
only the written signs and operational signals in ITU-R M.1677-1. The
accepted tokens are `<AR>`, `<AS>`, `<BT>`, `<CT>`, `<HH>`, `<SK>` and `<SN>`.
The ITU multiplication sign `×` shares the X signal and decodes as X.
Extended tokens `<BK>`, `<KN>`, `<KA>`, `<VE>` and `<SOS>` are rejected;
ordinary `SOS` remains three letters. Other symbols and Unicode
whitespace are rejected unless explicitly skipped. See the complete lists in
[Encoder POD](../lib/Ham/RTTY/Encoder.pm) and the shared-waveform table in
[Decoder POD](../lib/Ham/RTTY/Decoder.pm).

## Farnsworth practice and files

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
my $cw = Ham::RTTY->new(wpm => 20, effective_wpm => 12, frequency => 650);
$cw->write_wav('CQ TEST', $wav, bits => 24);
$cw->write_midi('CQ TEST', $midi, note => 77, program => 80);
my $result = $cw->read_wav($wav,
    frequency => 650, wpm => 20, effective_wpm => 12);
print $result->text, "\n";
for my $warning (@{$result->warnings}) {
    warn "$warning->{code}: $warning->{message}\n";
}
```

Generation defaults to 20 WPM. `effective_wpm` lengthens the letter and word
gaps for Farnsworth practice. Supply reception hints separately from the
constructor's generation settings. WAV files provide their sample rate in the
header; MIDI uses channels 1–16 and programs 0–127.

Parent directories must exist. To replace a file, pass `overwrite => 1`:
output is written to a temporary sibling and renamed after a successful close.
Failed generation preserves the old file. Permission bits are preserved;
ownership, ACLs and other hard links are not transferred. Detected symlinks are
rejected, but the directory must also be protected from concurrent writers.
See the [file reference](../lib/Ham/RTTY.pm) for cleanup and replacement details.

Per-call options leave the object's defaults unchanged. When changing `wpm`,
also change any previously set `effective_wpm` that should no longer apply.

## Samples, streaming and incremental reception

```perl
use strict;
use warnings;
use Ham::RTTY;

my $cw = Ham::RTTY->new(sample_rate => 8000, frequency => 650, wpm => 20);
my $next = $cw->stream_samples('SOS', block_size => 1024);
my $detector = $cw->detector(frequency => 650, wpm => 20);
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

my $samples = $cw->samples('SOS');
my $collected = $cw->decode_samples($samples, sample_rate => 8000, wpm => 20);
print $collected->text, "\n";
```

The iterator yields sample arrays, then `undef`. The detector rate must match
the array's actual rate; raw arrays carry no rate metadata. The factory inherits
sample rate/backend, but not generation tone or speed. A known tone is optional.
Each facade stream owns an independent generator; changing block boundaries
does not change its waveform within one backend.

`finish` is idempotent. Call `reset` before feeding more data; validation
failures preserve history. Previews can revise earlier text as audio arrives.
Unchanged snapshots are cached, but a new preview sorts the retained history
in O(N log N): request previews periodically, rather than after every block.
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

my $cw = Ham::RTTY->new;
my $timed = $cw->events('SOS');
my $sampled = to_samples($timed, 8000);
my $again = to_timed($sampled);
print validate_events($again), "\n";  # duration
my $decoder = $cw->decoder(wpm => 20);
$decoder->feed($sampled);
print $decoder->finish->text, "\n";
my $samples = $cw->generator(sample_rate => 8000)->generate($sampled);
my $midi_bytes = Ham::RTTY::MIDI->new(note => 77)->encode($timed);
print length($midi_bytes), " MIDI bytes\n";
```

Timed events use `unit => 'us'` and positive integer `duration` fields;
sampled events use `sample_rate` and positive integer `samples` fields.
Runs alternate `state => 'on'` and `state => 'off'`. Empty sequences and
leading/trailing OFF runs are valid. Across event-decoder feeds, equal states
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
my $cw = Ham::RTTY->new(sample_rate => 8000);
my $audio = Ham::RTTY::Audio->new(block_samples => 1024);
my $samples = $cw->samples('SOS');
my $next = $cw->stream_samples('SOS', block_size => 1024);
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

Audio methods do not decode Morse. Input supports seekable mono/stereo PCM
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

my $cw = Ham::RTTY->new;
my $wav = $cw->wav_bytes('SOS');
my $result = $cw->decode_wav_bytes($wav, wpm => 20);
print $result->text, "\n";
for my $warning (@{$result->warnings}) {
    warn "$warning->{code}: $warning->{message}\n";
}
my $all_fields = $result->as_hash;
my $midi = $cw->midi_bytes('SOS');

my $ok = eval { $cw->encode('CQ!'); 1 };
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
frames per block. Rates and frequencies are Hz; attack/release values are
milliseconds. The module POD lists each option's range and default.

`backend => 'perl'` needs only core Perl. `pdl` requires PDL 2.081 or later;
`auto` chooses PDL by availability, not speed. Small blocks can favor Perl.
See [measurements](benchmarks.md) and [architecture](architecture.md).

Run `perl -Ilib examples/workflows.pl` for a tour of the API.
The [example catalog](../examples/README.md) covers individual methods.

## Simultaneous stations

For distinct tones in a WAV recording, request all accepted channels:

```sh
ham-rtty receive --all-stations --json received.wav
ham-rtty receive --all-stations --wpm 20 --filter-bandwidth 80 received.wav
```

JSON is an array of up to eight full Results; plain output labels each line
with its candidate frequency. An empty array means no accepted station and
exit status 1. Ordinary `receive --json` instead returns one Result, including
rejection diagnostics. `--strict` returns 1 if any accepted station has warnings.
A WPM hint applies to every channel. Omit it when senders use different speeds;
a frequency hint selects one channel. `--min-snr-db` adjusts the raw tone/guard
power threshold (default 12 dB); it is not a calibrated receiver SNR control.

The library provides `read_wav_channels($path, %options)`,
`decode_wav_channels($seekable_handle, %options)` and
`decode_samples_channels($samples, %options)`. They return an array reference
of independent complete Results ordered by accumulated channel energy. The
incremental `Detector->channels` provides provisional or final snapshots.
These methods share the ordinary receive limits and options; see the
[complete Detector POD](../lib/Ham/RTTY/Detector.pm) for spacing, bandwidth,
latency and margin-suppression behavior. Co-channel stations cannot be
separated. Close tones, fading and noise can still cause false or missing
stations, even when text is present and no warning is emitted.

## Complete runnable scenarios

The [example catalog](../examples/README.md) covers PCM, streaming, reception,
results, errors and CLI use. Select an example with
`perl -Ilib examples/run-all.pl --only pcm-streams --backend auto`.

## Save and receive files

See the [practice-file recipe](#farnsworth-practice-and-files) for WAV and MIDI
output and WAV reception. Path methods open and close their own handles.

`write_wav` returns a statistics hash containing `state` and `samples`;
`write_midi` returns its byte count. `read_wav` returns a `Ham::RTTY::Result`.

## Symbol policy

The repertoire is strictly [ITU-R M.1677-1](https://www.itu.int/rec/R-REC-M.1677-1-200910-I/en),
Annex 1, Part I, sections 1.1.1–1.1.3: its letters, digits, written signs and
named operational signals.
No amateur-radio or extended Morse alphabet is enabled. `!`, `&`, `;`, `_`
and `$` are rejected. The accepted operational tokens are `<AR>`, `<AS>`,
`<BT>`, `<CT>`, `<HH>`, `<SK>` and `<SN>`; these are library mnemonics for the
ITU signals. `<BK>`, `<KN>`, `<KA>`, `<VE>` and `<SOS>` are not accepted.
`SOS` remains valid as three letters. `×` is encoded as X and decodes as X.
See [Encoder POD](../lib/Ham/RTTY/Encoder.pm) for the complete table and rules.

## Speed, spacing and reception

WPM means words per minute on a 50-unit reference scale. A dot lasts `1.2 / wpm`
seconds; actual message duration depends on its characters. Farnsworth practice
uses faster characters and longer gaps, for example `wpm => 20,
effective_wpm => 12`.

Constructor speed, spacing and tone configure **generation**. Supply known
`frequency`, `wpm` and Farnsworth `effective_wpm` on receiving calls separately.
WAV input supplies its own sample rate; raw sample input requires the actual
rate. Audio reception accepts explicit 1–60 WPM and estimates within 5–60 WPM.
The encoder and event decoder accept explicit speeds up to 200 WPM.

Invalid arguments, I/O failures and resource errors throw `Ham::RTTY::Error`.
Uncertain reception produces [Result warnings](../lib/Ham/RTTY/Result.pm).

## Choose an interface

| Task | Interface | Reference |
| --- | --- | --- |
| Ordinary text, samples and files | `Ham::RTTY` convenience methods | [POD](../lib/Ham/RTTY.pm) |
| Text symbols and Farnsworth events | `Ham::RTTY::Encoder` | [POD](../lib/Ham/RTTY/Encoder.pm) |
| Strict notation or incremental events | `Ham::RTTY::Decoder` | [POD](../lib/Ham/RTTY/Decoder.pm) |
| Event validation and unit conversion | `Ham::RTTY::Events` | [POD](../lib/Ham/RTTY/Events.pm) |
| Tone generation from custom events | `Ham::RTTY::Generator` | [POD](../lib/Ham/RTTY/Generator.pm) |
| Incremental sample reception | `Ham::RTTY::Detector` | [POD](../lib/Ham/RTTY/Detector.pm) |
| Raw PCM WAV without Morse decoding | `Ham::RTTY::Audio` | [POD](../lib/Ham/RTTY/Audio.pm) |
| MIDI export from custom events | `Ham::RTTY::MIDI` | [POD](../lib/Ham/RTTY/MIDI.pm) |
| Snapshots and exceptions | `Ham::RTTY::Result`, `Ham::RTTY::Error` | [Results](../lib/Ham/RTTY/Result.pm), [errors](../lib/Ham/RTTY/Error.pm) |

Read a module's manual with `perldoc`, for example `perldoc Ham::RTTY::Audio`.

## Optional PDL backend

Install PDL 2.081 or later into the Perl environment running your application,
then select `backend => 'pdl'` in the constructor or supported operation.
`backend => 'perl'` is the default. `backend => 'auto'` selects PDL when loadable,
otherwise Perl; it does not benchmark the workload. PDL needs a compatible
native build. Its benefit depends on operation, sample rate, tone hints and
buffer allocation. Acquisition and the biquad filters still run in Perl;
PDL accelerates the filtered spectral projections. See
[measured timings](benchmarks.md) for comparisons.

Both backends use the same public arrays and file/event formats. Floating-point
values can differ slightly, including one PCM unit near a rounding boundary.
Use `perl maint/benchmark.pl --help` and `perl maint/benchmark-platforms.pl --help`
to measure your own workload.

## Practical limits

WAV input supports mono/stereo PCM 8/16/24-bit; output is mono. Stereo `mix`
averages channels and may cancel opposite-phase audio; `left` or `right` selects
one. Compressed, float, extensible WAV and unknown-length streaming headers
are unsupported. MIDI output is standard file type 0.

Generation defaults to 10,000,000 total samples. Audio detection defaults to
24,000 retained frames, approximately 120 seconds including silence; event
decoding defaults to 100,000 retained runs. Increase the corresponding
`max_samples`, `max_frames` or `max_segments` explicitly when appropriate.
Streaming reduces block-buffer size but does not remove these history limits.
Every option's range and applicable method are specified in the POD.

Reception uses independent cascaded biquad band-pass channels, Hann windows,
and a Goertzel bank (equivalent projections with PDL). A raw spectral guard
rejects weakly distinguished noise before envelope timing. Distinct overlapping
CW tones can be decoded separately: `read_wav_channels`, `decode_wav_channels`
and `decode_samples_channels` return up to eight Results, each with frequency,
text and warnings. The ordinary methods return the strongest accepted channel.
From the command line:

```sh
ham-rtty receive --all-stations --json received.wav
```

A WPM hint applies to every station; omit it for independent estimates. A
frequency hint selects only that tone. The tests recover two simultaneous
messages at 150 Hz separation with 20 WPM hints and at 250 Hz separation with
independent 20/25 WPM estimates, with unequal levels and added noise. A stronger
continuous carrier is also tested. This does not establish arbitrary field
accuracy: co-channel stations cannot be separated; fading, interference, short
messages and unknown spacing can still produce wrong, partial or empty text.
Review each Result's warnings. The [verification record](verification.md)
reports the measured corpus revision, hinted and unassisted CER, and scope.
Run `perl maint/reception-corpus.pl` to repeat the measurements. The four
short beacon clips do not establish accuracy on human-keyed QSOs.

The default candidate spacing is 50 Hz. Synthetic reception tests allow tone
error within one configured grid step, an empirical tolerance rather than a
universal accuracy bound. Analysis uses approximately 20 ms Hann windows with
5 ms hops, preceded by two biquads per candidate. The window alone has about
70 Hz full half-power width. `filter_bandwidth` sets each biquad's width;
`min_snr_db` sets an acquisition tone/guard threshold, not calibrated radio SNR.
Candidate spacing, filter width and station resolving ability are distinct.
See the [Detector POD](../lib/Ham/RTTY/Detector.pm) for defaults, latency, memory,
station selection, margin suppression and preview limitations.
