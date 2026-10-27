# Security CI

[Overview](../README.md) · [Dependency audit](dependency-audit.md)

The reference workflow is retained with repository-specific names: full-history
redacted gitleaks; pinned actionlint and zizmor; unsafe Perl construct checks;
CPAN::Audit for installed dependencies/interpreter and declared constraints.
All actions are pinned to immutable revisions and permissions are job-scoped.
The aggregate security job requires every check to succeed.

No RTTY security audit result has yet been recorded. The copied CW audit data
was removed: its matches and outcomes are not evidence for this distribution.
Advisory triage remains an open release gate until the installed and declared
reports exist for this candidate. Do not whitelist or suppress unknown matches.

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
