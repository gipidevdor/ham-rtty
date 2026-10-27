# Verification history

[Overview](../README.md) · [Task guide](usage.md) · [Examples](../examples/README.md) · [Contributing](../CONTRIBUTING.md)

Archived from source revision `85eb8f3` during the 2026-10-25 refresh.
Individual measurement dates and source references below belong to their
original review. Undated sections cannot be assigned a new measurement date
or certified against today's source. All suite counts, coverage percentages,
packaging results and CI outcomes here are historical observations. See
[current verification](verification.md) and [current measurements](benchmarks.md).

## Checks preceding the channelized receiver

| Check | Result |
| --- | --- |
| Ordinary suite, macOS ARM64, Perl 5.44.0 with PDL 2.106 | 2,113 assertions across 27 files; PASS |
| Ordinary suite with all Perl warnings fatal | 2,113 assertions; PASS |
| System Perl 5.34.1 without PDL | 1,918 assertions across 27 files; PASS |
| Author checks | 410 assertions across 8 files; PASS |
| Perl::Tidy 20260826 and Perl::Critic 1.156 | PASS |
| Public POD headings, local links and executable documentation examples | PASS |
| Production statement coverage | 99.40% (1,816/1,827); PASS |
| Production branch coverage | 97.09% (633/652); PASS |
| Distribution build/test, archive checks and isolated installation | PASS |

The coverage figures are from the preceding runtime review, before the final
ITU symbol-table restriction. The restricted repertoire passed the ordinary,
author and documentation checks listed above.

Coverage checks require every production module, including the PDL implementation
and the internal snapshot builder. Missing or duplicate production paths fail
the gate before percentages are considered. No path was exempted to meet the
95% statement and 90% branch thresholds.

The corpus-license author check verifies the release inventory, audio hashes,
retained source-license evidence, attribution and included legal texts. It
rejects distributed audio outside the reviewed inventory. The local recording
without provenance is ignored and excluded by MANIFEST.SKIP. See
[NOTICE](../NOTICE) for the code/media license boundary.

## Channelized receiver checks

The ordinary suite passed 2,240 assertions across 28 files with Perl 5.44.0
and optional PDL, including with all warnings fatal. System Perl 5.34.1
without PDL passed 1,991 assertions across the same 28 files. It includes analytic biquad response and stability checks,
arbitrary filter chunk boundaries, two independent overlapping messages,
unequal levels with added noise, 150 Hz separation at explicit 20 WPM,
independent 20/25 WPM timing at 250 Hz separation, cached station snapshots,
recording-length preservation, scalar/PDL event equivalence and the all-station
sample/WAV/CLI interfaces. Existing impulse, sparse-message, fading, timing,
file and lifecycle regressions remain enabled.

Recorded author checks passed 453 assertions across nine files, including POD,
executable documentation examples, code style, metadata and media licensing.
The distribution archive and its isolated installation, command and examples
also pass. After integrating the existing upstream release/security changes,
all 2,693 ordinary and author assertions passed across 37 files with warnings
fatal. This runtime comparison referred to the historical receiver review.
Recorded production coverage was 99.43% of statements (2,098/2,110)
and 96.53% of branches (724/750), above the 95%/90% gates with every production
module included. These are statement/branch measurements; condition coverage
is not reported. The preceding table retains the earlier revision's figures.

## Regression evidence

The symbol repertoire is restricted to ITU-R M.1677-1. Extended procedure
tokens and unsupported punctuation are rejected; multiplication uses X.
Both decoder modes resolve admitted procedures consistently. Tests also cover batched silence without
phase changes, canonical event copies that ignore unrelated metadata, shared
configuration validation without throwaway instances, boundary-clamped median
seeds with independent observed-frame support and candidate-energy totals across backends/feeds/reset. Fresh previews
still sort/resegment retained history, O(KN log N) for K candidates and N frames, and examples throttle them.

Timing tests preserve the repeated-short-mark and shaped-mark regressions.
File tests cover permission/umask preservation and detected symlink rejection.
Inspection and rename are separate operations; the documentation states the
remaining concurrent-directory-change limitation. A stronger unkeyed carrier
is explicitly tested while the weaker CW is recovered, with and without a
frequency hint. Per-channel purity avoids counting the other tone in the
selected channel denominator. A separate independent schedule
varies mark/gap duration by up to 12%; it simulates irregular keying and is not
a human-keyed recording.

The reception matrix exercises 25, 50 and 100 Hz candidate steps. Tone error
is checked within one configured step, an empirical synthetic-test tolerance
rather than spectral resolution or a universal estimation bound. The receiver
now uses 20 ms Hann windows and 5 ms hops after cascaded band-pass biquads.

Four real clips from three radio-beacon recordings are now attributed and
licensed in [corpus/real/LICENSES.md](../corpus/real/LICENSES.md). Their text
references come from source descriptions. CER counts edits including spaces
and replacement characters; it is not capped at 100%. Observations from that review:

| Clip | CER with speed hint | CER estimated | Quality target (25%) |
| --- | ---: | ---: | --- |
| 4U1UN identification | 0% | 0% | Met |
| OH2B with calibration carriers/noise | 0% | 0% | Met |
| CS3B with calibration carriers/noise | 0% | 0% | Met |
| SK6RUD reception | 0% | 0% | Met |

The ordinary suite enforces recorded regression budgets, separately from the
quality target. Four clips of a few seconds each do not establish accuracy on
other recordings. `perl maint/reception-corpus.pl` emits current JSON measurements,
warning lists, targets and target status. These are automated beacons, not
human-keyed QSOs. Their failures and small corpus size limit accuracy claims;
co-channel transmitters and unlimited reception remain unsupported. Synthetic
station separation does not establish performance on arbitrary overlapping
off-air conversations.

The suite additionally covers fixed Morse vectors, independent synthetic
signals, PCM/MIDI bytes, malformed files, closed pipes, resource limits,
immutable snapshots and portable command-line workflows. Storable remains
required by public result/error copies; Hash::Util remains required by the
internal locked snapshot builder. Removing either prerequisite is unjustified.

## CI and release checks

The workflow contains twelve checks: six ordinary Perl combinations, five
PDL configurations and one author/distribution job. PDL covers Linux, macOS
ARM/Intel and Windows with Strawberry Perl; the minimum Perl 5.20 / PDL 2.081
combination uses Ubuntu 22.04's compatible compiler.

PDL and the pinned formatter use the setup action's dependency cache.
Successful dependency builds use normal installer output rather than verbose
compiler output, avoiding unrelated optional-module diagnostics being matched
as project failures. Cached installations remain subject to the complete test
suite. All twelve checks passed on the runtime commit above in
[run 40094023069](https://github.com/gipidevdor/ham-rtty/actions/runs/40094023069),
including production coverage, archive analysis and isolated installation.
See [CI runs](https://github.com/gipidevdor/ham-rtty/actions/workflows/test.yml)
for subsequent candidates. These checks are not CPAN Testers certification
or a PAUSE upload.

## Platform measurements before channelized reception

These measurements come from the successful twelve-job run above, on the
earlier runtime commit `da8c80d4c6b4a28e9972d89e689761eafd8a70ee`. The checked-in
[raw platform results](platform-history-results.json) retain the original rates,
iteration counts, elapsed times and environment metadata from all five
benchmark artifacts.

The workload was the literal message `CQ CQ DE TESTCALL` at 8000 Hz. PCM
cases read or write one second of mono WAV in memory, including validation,
headers and public array conversion, excluding disk I/O. Reception uses
either one complete feed or 4096-sample feeds. Each case warms up once and
then runs for at least one wall-clock second.
`maint/benchmark-platforms.pl` reproduces that protocol.

Each ratio is PDL calls/second divided by Perl calls/second on the same
runner. Values above 1 favour PDL; values below 1 favour Perl. These short,
single-run observations on shared hosted machines do not establish stable
backend rankings.

| Operation | Linux | macOS ARM64 | macOS Intel | Windows | Linux minimum |
| --- | ---: | ---: | ---: | ---: | ---: |
| Audio generation | 4.87x | 5.31x | 5.08x | 2.90x | 4.22x |
| Detection, complete array | 5.59x | 6.22x | 7.14x | 4.26x | 5.14x |
| Detection, 4096-sample feeds | 5.29x | 5.08x | 6.12x | 3.65x | 4.76x |
| PCM WAV read, 8-bit | 1.02x | 1.06x | 1.15x | 0.71x | 0.98x |
| PCM WAV read, 16-bit | 1.14x | 0.99x | 1.20x | 0.86x | 1.05x |
| PCM WAV read, 24-bit | 1.05x | 0.88x | 1.27x | 0.93x | 0.98x |
| PCM WAV write, 8-bit | 1.47x | 1.23x | 2.59x | 1.27x | 1.43x |
| PCM WAV write, 16-bit | 1.52x | 1.09x | 1.64x | 1.29x | 1.48x |
| PCM WAV write, 24-bit | 1.38x | 1.21x | 1.33x | 1.10x | 1.36x |

PDL accelerates synthesis and detection substantially in these cases. PCM
conversion has a smaller, workload-dependent benefit; some cases are slower
with PDL. The automatic selector chooses by availability, not measured speed.

## Dependency advisory review

The installed environment was audited with
`cpan-audit installed --perl --no-color --json`, CPAN::Audit 20261013.002
and advisory database 20261018.001. It reported three advisories, no scanner
errors and a nonzero exit status. The dependency audit is **not clean**.
Static review of these three matches found no confirmed product vulnerability,
but two environment-dependent questions remain:

- [Pod::Text margin handling](https://github.com/rra/podlators/commit/70510174f69eb54aa6d617bde4e1402cd9b7c61f.patch):
  podlators v6.0.2 is affected; update documentation tools to >=6.1.1.
  Ham::RTTY does not accept or render POD input, and CLI help is literal text.
- [File::Temp directory checks](https://github.com/Perl-Toolchain-Gang/File-Temp/issues/14):
  the audit lists every version with no fixed release. Ham::RTTY creates
  exclusive temporary files and does not rely on `_is_safe` as an input
  validator. Directory ownership/permissions still require review for hosts
  shared with hostile local users. Output paths are selected by the caller.
- [Perl regex cache overflow](https://github.com/Perl/perl5/commit/54cf3d44cbbedd17d774e9a37921963e8fd5d0cb.patch):
  the local Perl build source contains the upstream overflow guard, while
  the scanner matches the unchanged Perl version number. Binary provenance
  and consumer-provided runtimes remain deployment questions. CLI text is
  capped at 1 MiB, below the very large subject needed by this advisory;
  this does not certify every library consumer. Use a vendor-patched Perl.

The separate declared-constraints audit used a `cpanfile` generated from
`MYMETA.json` by CPAN::Meta/Module::CPANfile, preserving phases, relations and
optional PDL. `cpan-audit deps DIRECTORY --perl --no-color --json` reported
67 advisory matches, no scanner errors and a nonzero exit status. Broad
supported-version constraints include historical releases, so this is a
different result from the three installed-version matches, not 67 confirmed
vulnerabilities in the installed environment. Those additional constraint
matches have not received an individual applicability review.

Running `cpan-audit deps .` directly on this MakeMaker project did not audit
the declared prerequisites correctly; the generated manifest is the supported
input. See [security CI](security-ci.md) for the conversion and separate
installed/declared gates. No advisory was suppressed and no nonexistent fixed
version was substituted. This is a static review of the three installed
matches, not an exhaustive security audit or an exploit-validation result.

## Archived measurements

Earlier platform observations came from commit
`4e0a7e79a8e5d5fa76040d89d8c852c603667d67` in
[run 40086118418](https://github.com/gipidevdor/ham-rtty/actions/runs/40086118418).
The earlier [local benchmark data](benchmark-results.json) also predates the
corrections made during that review. Those measurements do not describe the corrected
estimator or snapshot path.

### Archived message-length timings (2026-10-24)

These earlier measurements, also preceding the corrections made during that review, use the literal message `CQ DE TESTCALL`, repeated
one, two, four, eight or twelve times with one separating space. Message
length is the actual character count including spaces, and audio duration
comes from the generated events. No reference-word equivalence is used.
These measurements replace the previous message-length example.

The sample rate was the default 16000 Hz at 20 WPM, on macOS ARM64 with
Perl 5.44.0 and PDL 2.106. Each processing time is the median of three
new runs, in seconds.

| Repeated messages | Characters, including spaces | Audio duration | Generate, Perl | Generate, PDL | Analyze, Perl | Analyze, PDL |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 14 | 7.14 | 0.076 | 0.011 | 0.381 | 0.056 |
| 2 | 29 | 14.70 | 0.154 | 0.024 | 0.782 | 0.112 |
| 4 | 59 | 29.82 | 0.310 | 0.050 | 1.580 | 0.230 |
| 8 | 119 | 60.06 | 0.619 | 0.104 | 3.186 | 0.471 |
| 12 | 179 | 90.30 | 0.935 | 0.158 | 4.781 | 0.706 |

Generation measures sample synthesis, including generator construction.
Analysis measures 4096-sample feeds and finalization with the default
frequency search grid; detector construction is outside that timer.
The audio is already available in memory. PCM conversion, file I/O and
live reception time are excluded. These are measured cases, not estimates
extrapolated from the short CI benchmark.

Default reception retains at most 24000 frames, approximately 120 seconds
including silence. Longer recordings require a larger explicit `max_frames`
and more retained memory. The time needed to transmit or receive the audio
in real time remains its full audio duration.

## CLI integration

The installed `ham-rtty` command shares the library's encoding, file and
reception paths. The integrated tests include subprocess UTF-8/CRLF input,
text and binary outputs, option validation, exit codes, bounded WAV stdin,
strict warnings, protected output replacement and closed pipes. The installer
checks all six commands and the Windows launcher in a path containing spaces.
The coverage numbers above included the CLI implementation and biquad filter;
every production module must be present before the coverage gate can pass.

## Security audit corrections after packaging

The subsequent correction updates vulnerable build/author prerequisites and
uses a tested discovery adapter while retaining each original scanner report.
Installed-version matches fall from three to two; correctly scoped declared
matches fall from the original 67 to 38. Both gates remain nonzero. See
[security CI](security-ci.md#historical-corrective-local-results-2026-10-24) for versions,
remaining components and the distinction between compatibility and security.
That security-only correction did not change the runtime implementation.
The later channelized receiver and its local measurements are described above.

## Merge preparation checks

The test-only Digest::SHA requirement is at least 5.96, excluding the historical
CVE-2016-1238 range introduced by an unconstrained test prerequisite. CI installs
it explicitly for ordinary and PDL jobs, including older supported Perls.
The installed dependency audit on the receiver branch matched the pre-existing
main-branch report exactly; the known baseline advisories are not suppressed.

The author job runs the full coverage suite with two processes and collects
statements, branches and conditions. Condition instrumentation preserves complete
branch counts; unrelated subroutine/POD/timing collection is unnecessary for
the statement/branch gates. The job has a 60-minute ceiling for the heavier
channel bank, coverage and archive/install checks. The full production inventory
and 95% statement / 90% branch thresholds remain unchanged.
