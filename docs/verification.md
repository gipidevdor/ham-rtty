# Verification

Development candidate 0.01, measured 2026-10-27. **Not release-qualified.**

Production code revision `3627c44`; final documentation commits may follow. Local environment: Apple M4, macOS ARM64, Perl 5.44.0, PDL 2.106. [Raw verification](verification-results.json), [coverage](coverage-results.json), [performance](performance-results.json) and [security triage](security-audit-results.json) retain the evidence. No results are inherited from Ham::CW.

## Local checks

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

**Four real RTTY recordings remain missing.** The [inventory](../corpus/real.json) contains explicit placeholders; no field CER or regression budget is invented. `perl maint/reception-corpus.pl` intentionally fails until licensed, independently annotated fixtures are admitted. The ≤25% CER target is unchanged.

## Performance and memory

Three-iteration CPU/wall benchmarks at 8/16 kHz and 4096-sample blocks are recorded in [benchmarks](benchmarks.md). At known tones the Perl CPU R is 0.0179 at 8 kHz and 0.0347 at 16 kHz; these are short local synthetic workloads. PDL helps some operations and is slower in others. `auto` selects availability, not speed.

The requested 120-second, 48000-Hz `read_wav` workload used 20,758,528 bytes (**19.80 MiB**) peak RSS in a fresh process, excluding fixture generation. Exactly 5,760,000 samples were analyzed. The fixture intentionally cuts a frame at its end, producing an incomplete-frame warning. This measures the requested workload, not every possible option combination.

## Security and release limits

The installed audit reports 2 matches and the declared audit 38, no scanner errors; both exit 1. Each advisory has a recorded triage assessment and upstream references. The development URI minimum was raised to 5.36 to resolve one declared match. No advisory exclusion hides remaining matches. Legacy compatible interpreters must be patched; compatibility does not certify deployment safety. See [security CI](security-ci.md).

The copied 12-job workflow structure covers Linux, macOS ARM64, macOS Intel, Windows, minimum/current Perl and five PDL configurations. **Hosted CI has not run for this repository.** Static minimum-version analysis and local 5.44 tests do not establish successful runtime behavior on all other versions/platforms.

Real-recording acceptance and a clean dependency gate remain mandatory. This candidate must not be labelled a verified 1.0 or uploaded to CPAN as release-qualified until those gates and the hosted matrix pass. See the [release checklist](releasing.md) and [standards/provenance](standards.md).

Commit identifiers were updated before first publication to use the author's GitHub noreply address. This changes commit metadata only; measured production-file hashes and code are unchanged.

## Copyright and documentation update, 2026-10-27

The README and guide index now follow the reference project's section and
navigation structure. Copyright (c) 2026 Giacomo Picchiarelli is explicit in
NOTICE, the README, the guide index, every public module's POD and every
rendered site's footer. The Artistic 2.0 license text and the reference CSS
remain byte-identical to Ham::CW f9a1dac. No signal-processing code changed.
The updated author run passed all 12 files and 679 assertions, including
copyright checks for every rendered page and every public module.
