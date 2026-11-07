# Security CI

[Overview](../README.md) · [Dependency audit](dependency-audit.md)

The reference workflow is retained with repository-specific names: full-history
redacted gitleaks; pinned actionlint and zizmor; unsafe Perl construct checks;
CPAN::Audit for installed dependencies/interpreter and declared constraints.
All actions are pinned to immutable revisions and permissions are job-scoped.
The aggregate security job requires every check to succeed.

Local and hosted audit results are recorded for this distribution in the dated
sections below. Open advisory matches remain a release gate. Results from
Ham::CW are not substituted for Ham::RTTY evidence; no unknown advisory is
whitelisted or suppressed.

For each match record advisory ID, affected installed/declared version, runtime
reachability, remediation and residual risk. Keep scanner/database versions and
JSON artifacts. Broad supported ranges and development dependencies are not
excused merely because they are optional or outside the default runtime.

Local safe-I/O tests cover exclusive output, failed replacement preservation,
malformed/truncated RIFF and bounded processing. These tests do not replace
the dependency audit or hosted workflow analyzers.

## Local audit and triage, 2026-10-27

The local installed audit reports **2 matches**; the declared audit reports
**38 unique distribution/advisory matches**, both with exit 1 and no scanner
errors. Tools: CPAN::Audit 20261013.002, CPANSA::DB 20261018.001. Exact IDs,
affected/fixed ranges, references, scopes, report hashes and a per-advisory
triage entry are retained in [security-audit-results.json](security-audit-results.json).
No exclusion was added. The gate remains failing.

| Dependency | Assessment and action |
| --- | --- |
| Perl | Supported legacy interpreters overlap 29 advisories. Fixed regexes reduce some paths; they do not establish interpreter safety. Require patched deployments and verify patch provenance. The installed 5.44.0 still matches CVE-2026-15534 in this database. |
| File::Temp | The reported `_is_safe` symlink issue concerns MEDIUM/HIGH safe-level checks. This library does not set safe_level; caller-global configuration can change it. Keep the upstream match active; no fixed release is listed. |
| Encode | Three declared legacy matches; CLI processes external UTF-8 via Encode. Current installed Encode is not the same claim as safe support for all older bundled versions. Use patched interpreters/core modules. |
| Storable | Three declared matches concern malformed serialized input/hook records. Public snapshots validate plain acyclic unblessed data before dclone, and the library exposes no thaw/retrieve API. These specific serialized-input routes are not exposed; the dependency gate remains active. |
| PathTools | Two declared matches apply to permitted old Cwd/File::Spec versions used by tests/tools. Test-only scope does not excuse unsafe build environments. |
| URI | Raised the development lower bound from 5.00 to 5.36 to exclude the database's non-NFC-hostname advisory. This removed one declared match; it adds no runtime dependency. |

Primary evidence: [File::Temp issue 14](https://github.com/Perl-Toolchain-Gang/File-Temp/issues/14)
and the [Perl superlinear-cache fix](https://github.com/Perl/perl5/commit/54cf3d44cbbedd17d774e9a37921963e8fd5d0cb).
The local interpreter's directory mentions that CVE; this record does not infer
patch application from a directory name. The raw report continues to show the
match. Software compatibility with Perl 5.20 is not a promise that an unpatched
historical interpreter is safe to deploy.

`actionlint` 1.7.12 accepts the three workflows locally. Gitleaks 8.30.1
found no leaks in the six existing commits or the uncommitted source scan,
with redacted JSON evidence. Zizmor 1.31.1, offline with the auditor persona,
reports no findings: explanatory Pages permission comments were added and the
coverage-directory expression moved from shell text into an environment variable.
The ordinary persona's two low findings were fixed rather than suppressed.
All four unsafe-Perl-construct policies pass. Dependency advisories still keep
the overall security gate failing; local scans are not hosted CI results.

## Dependency minima and CI diagnosis, 2026-10-30

The declared requirements now exclude Encode versions below 3.12, Storable
versions below 3.41 and test-tool Cwd/PathTools versions below 3.65. Both JSON
and legacy YAML metadata are checked against vulnerable/fixed boundaries.
Ordinary and PDL jobs install declared dependencies before testing, including
on Perl 5.20. The package version remains 0.001.

With the same CPANSA::DB 20261018.001 snapshot before and after, declared
matches fall from **38 to 30**, with no scanner errors. Eight advisory ranges
for Encode, Storable and PathTools are excluded by the new minima. No advisory
exclusion, phase suppression or changed gate is used. The
[raw remediation record](ci-remediation-results.json) retains source revisions,
removed/remaining IDs, metadata checks and the hosted baseline.

The installed audit in [run 41116933237](https://github.com/gipidevdor/ham-rtty/actions/runs/41116933237)
reports File::Temp 0.2312 and Perl 5.44.0 matches. Those database entries list no
fixed version. Remaining declared matches include interpreter advisories
overlapping the supported Perl range. The
[File::Temp upstream issue](https://github.com/Perl-Toolchain-Gang/File-Temp/issues/14)
remains open. A locally named patched interpreter does not establish that the
GitHub runner has that patch. The audit therefore remains failing.

Pages already publishes four licensed off-air clips and a generated example in
[the free corpus](../corpus/free/README.md); ordinary tests exercise them.
Their minimodem references are explicitly labelled non-authoritative. The
separate [release inventory](../corpus/real.json) still contains four missing
independently annotated entries, so the author job fails at
`maint/reception-corpus.pl`. Archive/install checks now run before that gate,
so its missing data no longer skips package verification. Available examples are retained with their stated
reference limitations. These remaining failures cannot be reported as passing
CI on the evidence currently recorded.

## Interpreter remediation and inventory correction, 2026-11-07

The latest inspected hosted [run 41499662145](https://github.com/gipidevdor/ham-rtty/actions/runs/41499662145)
used CPAN::Audit 20261013.002 and CPANSA::DB 20261101.010. Its installed report
contains **4 distribution/advisory matches**: File::Temp 0.2312
(CVE-2011-4116), Perl 5.44.0 (CVE-2026-15534), and Sereal::Encoder and
Sereal::Decoder 6.003 (both CVE-2018-12913). These represent three distinct
CVEs. Both audit steps failed with exit 1 and no scanner errors; the declared
report still contains **30 matches**. The other three security jobs passed.
The older two-match records above remain historical evidence.

The Security workflow now builds Perl 5.44.0 with both upstream patches using
[`maint/build-security-perl.sh`](../maint/build-security-perl.sh):

- [568e6fd238867bb9e99fa3f47cba3169009239e0](https://github.com/Perl/perl5/commit/568e6fd238867bb9e99fa3f47cba3169009239e0)
  changes the superlinear-cache countdown to support unsigned arithmetic.
- [54cf3d44cbbedd17d774e9a37921963e8fd5d0cb](https://github.com/Perl/perl5/commit/54cf3d44cbbedd17d774e9a37921963e8fd5d0cb)
  uses STRLEN counters and checks the allocation calculation for overflow.

The builder verifies the archive and both patches with SHA-256 before
extraction or application, applies patches without fuzz, and requires Perl's
core and extension regex tests to pass before installation. It refuses to
reuse an existing build directory. The workflow selects the resulting Perl
for dependency installation, metadata generation and auditing; it invokes
the bootstrap cpanm script explicitly with that interpreter. Input checksums,
regex test output and `perl -V` join the saved audit artifacts. This is a
configured environment correction, not evidence of a passing hosted run.

The adapter also repairs an installed-inventory gap: CPAN::Audit only checks
versions enumerated in its database. An installed version absent from that
list could previously report zero advisories, even when an open affected
range included it. The adapter adds observed installed versions to an
in-memory copy of the release inventory, leaving the source database and all
advisory ranges unchanged. CPAN::Audit still performs the matching. Tests
cover unlisted vulnerable and fixed versions, an open-ended advisory, and
an interpreter absent from the database's version inventory.

Sereal 7.001 illustrates that gap with the inspected database: an exact query
returns no match because the release is unlisted. Its packaged `miniz.c` and
`miniz.h` are byte-for-byte identical to 6.003. Upgrading solely to obtain that
empty report would not demonstrate remediation. The installed adapter retains
the advisory. Sereal enters the CI environment through Devel::Cover's optional
dependencies; it is not used by the library or CLI. Hosted coverage currently
uses a fresh local database, but other callers can supply coverage databases.
The [Miniz report](https://github.com/richgel999/miniz/issues/90) and its
applicability to Sereal's bundled implementation need upstream resolution.

File::Temp's upstream issue remains open and the database lists no fixed
release. The library does not select the affected MEDIUM/HIGH safe-level
checks, but that is not a package fix. Output and temporary parent directories
must be trusted; final-component symlink rejection does not establish that
parent-directory trust. No exception or replacement dependency was introduced.

The patched interpreter retains version 5.44.0 and therefore still matches
the database's `>0` Perl advisory. Declared support for Perl >=5.20 also
continues to overlap the historical interpreter advisories. The compatibility
contract, declared constraints and failing security gate are retained. A
green gate requires evidence-backed upstream advisory corrections or fixed
releases and a separate decision about supported deployment versions.

Local verification on macOS completed the builder and all 558,441 assertions
in 89 core/extension regex test files. Ham::RTTY's pure-Perl suite passed
2,345 assertions in 22 files; after rebuilding PDL 2.106 for the new interpreter,
the same suite passed 2,649 assertions. The audit and minimum-syntax checks
passed 73 assertions. A Sereal 7.001 inventory fixture against CPANSA::DB 20261101.010
reproduced zero stock matches and two corrected matches, with no errors.
ShellCheck, actionlint and the modified adapter's Perl::Critic/style checks
passed. The upstream oversized-subject memory-corruption trigger was not
executed; the verified upstream patches and core regex suite are the focused
substitute. Hosted Linux execution remains unverified.
