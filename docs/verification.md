# Verification

Development candidate 0.001, measured 2026-10-27. **Not release-qualified.**

## Current verification summary

Supplementary [FreeBSD and Cygwin portability tests](portability.md) pass in all
three environments on 2026-10-30: 21 files / 1,905 assertions each, followed by
the example catalog and installed CLI checks. Their [raw record](portability-results.json)
keeps environment versions and source hashes separately from the local evidence below.

Source `f7cc5d908426b1a7d07eeb7fc4d96b671f940755` corrects incremental event timing, expanded history limits,
merged-run accounting and rounded idle segments. Reception Results are documented
as integer-microsecond TimedEvents. Version remains **0.001**.

| Check | Current local result |
| --- | --- |
| Warnings-fatal ordinary suite | 21 files, 2,099 assertions, PASS |
| Author suite | 12 files, 826 assertions, PASS; no skipped files |
| Correctness regressions | 40 assertions, PASS |
| Statement coverage | 1,771 / 1,772 = 99.94% |
| Branch coverage | 622 / 640 = 97.19% |
| Per-module coverage gate | Every production module passes 95% statements and 90% branches |
| Distribution | Archive checks, isolated installation, CLI and examples PASS |

[Raw correctness results](correctness-results.json) retain source hashes,
commands, per-module coverage and regression cases. The prior source fails six
of the first ten assertions and then aborts at its history-limit defect.
The new tests compare complete results at 44.1/384 kHz with one sample per feed,
exercise reset and unit changes, preserve rejection atomicity and verify
100,001-segment paths. No coverage points are excluded.

Earlier CPU/RAM measurements and hosted runs below remain tied to their own
revisions; they are not relabelled as measurements of this fix. The missing
reviewed off-air recordings and dependency audit remain open release gates.

## Verification before incremental correctness fixes

Production source `084dbc682b3fc29714a0b9e8c0ffcab0424bc770` contains the
bounded receiver. Later changes through `bad2d2f6f56b56590bb84bedbb2f8f4f252021fd`
update documentation and benchmark evidence. Version remains **0.001**.

| Check | Latest recorded result |
| --- | --- |
| Warnings-fatal ordinary suite | 20 files, 2,059 assertions, PASS |
| Author suite | 12 files, 824 assertions, PASS |
| Statement coverage | 1,750 / 1,751 = 99.94% |
| Branch coverage | 607 / 622 = 97.59% |
| Per-module coverage gate | Every production module passes 95% statements and 90% branches |
| Distribution | Archive checks and isolated installation, CLI and examples PASS |
| Hosted compatibility | All eleven jobs pass on `bad2d2f` |
| Reviewed off-air recording acceptance | FAIL: four independently annotated fixtures remain missing |
| Dependency CVE audit | FAIL: findings remain open; no exclusions added |

[Current coverage and RAM evidence](memory-optimization-results.json),
[current local performance](performance-results.json),
[five-platform performance](platform-results.json) and
[raw verification](verification-results.json) retain their own measured revisions.
The [latest hosted run](https://github.com/gipidevdor/ham-rtty/actions/runs/40528671415)
passes six ordinary Perl and five PDL compatibility jobs. Its author job fails
at real-recording acceptance. Documentation deployment passes in
[run 40528671622](https://github.com/gipidevdor/ham-rtty/actions/runs/40528671622);
the dependency audit remains failing in
[security run 40528671418](https://github.com/gipidevdor/ham-rtty/actions/runs/40528671418).
These results do not qualify a CPAN release.

For memory-sensitive file workflows use `read_wav` and `write_wav`; use
`stream_samples` to consume generated blocks. Perl remains the default and
PDL is optional. Input is processed in bounded pieces, search keeps only the
initial half second and native projection matrices are capped at 65,536 cells.
Frame/run budgets are checked before WAV PCM reads. Result history is retained
within configured limits; streaming does not imply constant memory for every
recording length. See [memory-conscious operation](usage.md#memory-conscious-operation).

The latest local timing run uses source `6b03600`, four 8/16-kHz known/search
commands, three calls per operation and separate sample/WAV/generation timers.
[Benchmarks](benchmarks.md) include wall ratios, CPU totals, RAM ranges and
repeat commands. CI rate measurements use a separate protocol and known default
tones. Earlier results below remain tied to their original revisions.

## Initial verification record

Production code revision `3627c44`; final documentation commits may follow. Local environment: Apple M4, macOS ARM64, Perl 5.44.0, PDL 2.106. [Raw verification](verification-results.json), [coverage](coverage-results.json), [performance](performance-results.json) and [security triage](security-audit-results.json) retain the evidence. No results are inherited from Ham::CW.

### Initial local checks

| Check | Observed result |
| --- | --- |
| Warnings-fatal `make test` | 17 files, 1,796 assertions, PASS |
| Author suite | 12 files, 630 assertions, PASS |
| Statement coverage | 1,696 / 1,697 = 99.94% |
| Branch coverage | 582 / 596 = 97.65% |
| Per-module coverage gate | Every production module reaches 95% statements and 90% branches; branchless module is N/A |
| Distribution | `make distcheck`, `make disttest`, archive contract, isolated installation, installed CLI and examples PASS |
| Public POD and examples | Every public method has its own POD heading; all module synopses and README/usage Perl recipes execute |
| Style | Pinned Perl::Tidy 20260826 and repository Perl::Critic severity 3 pass |
| Metadata / manifest / minimum version / spelling | PASS, including static Perl 5.20 analysis and codespell 2.4.1 |
| Documentation site | 38 HTML pages; 1,735 local links/anchors checked; browser inspection passed |
| Workflow analyzers | actionlint 1.7.12 and zizmor 1.31.1 auditor persona pass without findings |
| Unsafe constructs / secrets | Four Perl policies pass; gitleaks 8.30.1 reports no leaks |

Coverage includes statement, branch and condition instrumentation, both numerical backends and production-module inventory validation. `maint/coverage.pl` checks each module separately; it does not substitute an aggregate percentage. No coverage points were marked uncoverable. The one uncovered statement is the return after a throwing backend error. Raw per-module counts are retained.

```sh
HARNESS_PERL_SWITCHES='-Mwarnings=FATAL,all' make test
make distmeta
prove -lr xt
HARNESS_PERL_SWITCHES='-MDevel::Cover=-db,/tmp/ham-rtty-cover-release,-blib,0,-coverage,statement,branch,condition,-select,lib/Ham,-ignore,^t/' prove -j2 -lr t
perl maint/coverage.pl /tmp/ham-rtty-cover-release
```

Author checks need the development prerequisites plus codespell on PATH. A skip caused by a missing optional author tool is not a release pass. The recorded run executed all 12 files without skips.

## Reception evidence

Every assigned character in both ITU and US tables round-trips through notation, bits and events. Independent S.1 numeric vectors verify the mapping instead of relying only on paired encoder/decoder agreement. The synthetic matrix uses seeded random mixed-case input with figures/punctuation at 8/16 kHz, baud 45.45/50/75, shift 170/450/850 and stop 1/1.5/2, through samples and WAV, on Perl and PDL. Text expectations agree across backends.

Additional tests cover uniform white noise at a theoretical 16.7 dB SNR with 0% CER for the fixed test message, ±2% baud mismatch, ±20 Hz tone offset, reversed polarity, independent S.1-frame oscillators, unequal tone levels, a stronger 1100 Hz carrier, mid-stream resynchronisation, bad stops, USOS and repeated shifts. Backend waveform/chunk equality and PCM 8/16/24-bit conversions are checked separately. These cases establish synthetic behavior, not general radio accuracy.

**Four release-quality, independently annotated fixtures remain missing.** Licensed exploratory examples are now available in [the free corpus](../corpus/free/README.md); their independent decoder outputs are not authoritative transcripts. The [inventory](../corpus/real.json) contains explicit placeholders; no field CER or regression budget is invented. `perl maint/reception-corpus.pl` intentionally fails until licensed, independently annotated fixtures are admitted. The ≤25% CER target is unchanged.

## Initial performance and memory

Three-iteration CPU/wall benchmarks at 8/16 kHz and 4096-sample blocks are recorded in [benchmarks](benchmarks.md). In that initial run, at known tones the Perl CPU R was 0.0179 at 8 kHz and 0.0347 at 16 kHz; these are short local synthetic workloads. PDL helps some operations and is slower in others. `auto` selects availability, not speed.

The initial 120-second, 48000-Hz `read_wav` workload used 20,758,528 bytes (**19.80 MiB**) peak RSS in a fresh process, excluding fixture generation. Exactly 5,760,000 samples were analyzed. The fixture intentionally cuts a frame at its end, producing an incomplete-frame warning. This measures the requested workload, not every possible option combination.

## Security and release limits

The installed audit reports 2 matches and the declared audit 38, no scanner errors; both exit 1. Each advisory has a recorded triage assessment and upstream references. The development URI minimum was raised to 5.36 to resolve one declared match. No advisory exclusion hides remaining matches. Legacy compatible interpreters must be patched; compatibility does not certify deployment safety. See [security CI](security-ci.md).

The copied 12-job workflow structure covers Linux, macOS ARM64, macOS Intel, Windows, minimum/current Perl and five PDL configurations. The hosted matrix has now run on this repository; see the dated evidence below. Local measurements above remain tied to their recorded revisions.

Real-recording acceptance and a clean dependency gate remain mandatory. This candidate must not be labelled a verified 1.0 or uploaded to CPAN as release-qualified until those gates and the hosted matrix pass. See the [release checklist](releasing.md) and [standards/provenance](standards.md).

Commit identifiers were updated before first publication to use the author's GitHub noreply address. This changes commit metadata only; measured production-file hashes and code are unchanged.

## Copyright and documentation update, 2026-10-27

The README and guide index now follow the reference project's section and
navigation structure. Copyright (c) 2026 Giacomo Picchiarelli is explicit in
NOTICE, the README and every public module's POD. Site footers and the guide
index follow Ham::CW, without repeated personal credits. The Artistic 2.0 license text and the reference CSS
remain byte-identical to Ham::CW f9a1dac. No signal-processing code changed.
The updated author run passed all 12 files and 679 assertions, including
copyright checks for every public module. Footer checks now enforce the
reference layout without repeated personal credits.

## Shared reference alignment, 2026-10-27

Compared common implementations directly with Ham::CW f9a1dac. After
package/distribution/command/error-prefix and version substitution, and the
same Perl::Tidy formatting, 21 common implementations match. Audio and Error
comparisons cover executable code; their RTTY examples use different signal
parameters. The other entries compare complete file content. The
[raw verification](verification-results.json) lists the compared files.

Restored the reference guide structure, shared recipes, example runner,
catalog and isolated example test. The catalog contains ten scenarios and
covers every public method and CLI command. Single-station reception replaces
the CW multichannel example. Missing real recordings are checked separately;
no synthetic example is presented as a received-radio fixture.

Warnings-fatal ordinary tests passed 18 files and 1,952 assertions. Author
checks passed 12 files and 716 assertions. Signal-processing implementations
are unchanged; the restored file tools and examples use RTTY options.

## Hosted CI, 2026-10-27

On revision `008eca1891d2c926b49a8c807851722df451542b`, all eleven
[compatibility jobs](https://github.com/gipidevdor/ham-rtty/actions/runs/40493543001)
passed: six ordinary Perl jobs and five PDL jobs across Linux, macOS ARM64,
macOS Intel and Windows, including Perl 5.20 and PDL 2.081. The author job
failed at real-recording acceptance because all four reviewed fixtures are
missing. The dependency audit also remains a separate failing gate.
The raw verification records individual hosted job results and run URLs;
these results do not replace the earlier local measurements or qualify a release.

Dependabot [PR #1](https://github.com/gipidevdor/ham-rtty/pull/1) and
[PR #2](https://github.com/gipidevdor/ham-rtty/pull/2) update the official Pages
configuration and artifact actions to 6.0.0 and 5.0.0. Both pins match their
upstream release commits. Documentation build/upload and workflow security
checks passed on both updated PR heads before merging. The configuration
action uses Node 24 on GitHub-hosted Ubuntu; artifact upload retains the
existing site path and permissions. No release gate was removed or weakened.

## Ergonomics review, 2026-10-27

Source revision `1286e5990f189c68a7c44f73dd26af2a8cdce461` corrects the CLI
quick start's mismatched baud settings, the streaming guide's omitted tone,
and default search bounds that rejected valid low-rate recordings. Help shows
tone units, channel choices and command-specific limits. Events, WAV and MIDI
now report explicit lenient substitutions on stderr while preserving usable
JSON and binary stdout. User-owned installation instructions configure both
module and command lookup. Version remains **0.001**.

Warnings-fatal ordinary tests pass 18 files and 1,980 assertions; the author
suite passes 12 files and 717 assertions. Regression checks execute the help
workflow in an empty directory, assert the streaming guide's actual text,
exercise known-tone/searching low-rate reception on both backends and reject
explicit invalid search bands. Distribution checks and an isolated install
with the complete installed example catalog pass.

Fresh coverage is 1,711/1,712 statements (**99.94%**) and 594/608 branches
(**97.70%**). Every production module passes the 95%/90% gate. The
[raw verification](verification-results.json) retains module counts, source
hashes, commands and the tested archive hash separately from older results.
Earlier timing/memory measurements have not been repeated for this revision.
Missing reviewed recordings and the dependency audit still prevent release
qualification.

## Free reception examples, 2026-10-27

Added three distinct DWD radio captures under CC BY 4.0, an amateur contest
excerpt under CC0 1.0 and an externally generated Wikimedia signal with a
public-domain dedication. Source pages, author credits, original-download and
derivative hashes, exact conversions and independent decoder commands are
retained in [the inventory](../corpus/free.json) and
[licence notices](../corpus/free/LICENSES.md).

With the unchanged production modules from `74cd1b1`, Perl and PDL report the
same disagreement rates against minimodem 0.24: 5.23%, 4.07% and 11.86% for
the three DWD excerpts, 20.00% for the amateur excerpt and 0.00% for the
external generated signal. CRLF/bare CR are explicitly converted to LF for
this comparison only. Warnings and raw decoded text remain in the
[measured report](reception-examples-results.json).

These are offline interoperability/regression examples, not verified field
CER. Other examined recordings decoded poorly or lacked established
parameters; selection was not random. The independently annotated field
acceptance gate and dependency audit remain unchanged. No release-qualified
claim follows from these decoder comparisons.

The complete review passes 19 ordinary test files / 2,030 assertions and 12
author files / 822 assertions, plus the distribution inventory, archive
contract and isolated installation with all installed examples. All eleven
[hosted compatibility jobs](https://github.com/gipidevdor/ham-rtty/actions/runs/40513649394)
pass on the fixture commit. Workflow analyzers and the local secret scan
report no findings. These results do not claim a passing dependency audit or
authoritative field acceptance.

## Perl and PDL RAM comparison, 2026-10-27

Thirty successful isolated observations cover the initialized toolkit,
120-second/48000-Hz WAV reception, a 30-second/8000-Hz DWD recording, streamed
generation and collected generation. Each workload/backend has three runs.
The [benchmark table](benchmarks.md#peak-resident-memory) reports median and
minimum/maximum peak RSS; [raw RAM results](memory-results.json) retain every
observation and source/input hashes.

For 120-second WAV reception, median peaks are 20.70 MiB (Perl, PDL unloaded)
and 27.55 MiB (PDL); largest observed peaks are 20.75 and 27.58 MiB. Each run
analyzes all 5,760,000 samples and both backends return identical text.
Production modules are unchanged; the benchmark helper adds explicit backend
selection and isolated workload modes. Earlier CPU and RAM observations
remain historical and are not relabelled as new measurements.

## Bounded reception memory, 2026-10-27

Source `084dbc682b3fc29714a0b9e8c0ffcab0424bc770` keeps Perl and streamed
WAV I/O as defaults, processes caller-sized arrays in bounded pieces, acquires
from exactly the initial half second and bounds optional PDL projection
matrices. Header-declared frame/run budgets are checked before PCM reads.
Public data types, sample rates, snapshots and existing ceilings are preserved.

A paired 30-process comparison reduces median peak RSS for a 960,000-sample
feed from 85.81 to 48.19 MiB (Perl) and 92.69 to 54.98 MiB (PDL). A supported
384-kHz/20-baud PDL search stress case falls from 365.11 to 53.52 MiB; its
median process wall time increases from 2.42 to 3.45 seconds. Ordinary
120-second WAV reception remains around 20.8/27.6 MiB. Complete results,
including diagnostics and warnings, agree before/after and across repetitions.
The [benchmark protocol](benchmarks.md#bounded-reception-and-recommended-defaults)
and [raw comparison](memory-optimization-results.json) preserve both revisions,
hashes, ranges and native timer output.

Warnings-fatal ordinary checks pass 20 files / 2,059 assertions; author checks
pass 12 files / 824 assertions. The original implementation fails 9 of the
29 added regression assertions; the new implementation passes all 29. Fresh
coverage reaches 1,750/1,751 statements (99.94%) and 607/622 branches (97.59%),
with every production module passing its 95%/90% gate. Raw module counts are
in the comparison report. No coverage points are excluded. Independent
field transcripts and the dependency audit remain open release gates.
