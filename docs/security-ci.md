# Security checks in CI

[Overview](../README.md) · [Task guide](usage.md) · [Examples](../examples/README.md) · [Contributing](../CONTRIBUTING.md)

Recorded runs and advisory results are listed below by source revision and
date. See [verification](verification.md) for the corresponding test results.

`.github/workflows/security.yml` runs on pull requests, pushes to main,
manual dispatch and every Monday at 06:23 UTC. The weekly scan refreshes the
advisory database even when no code changes. The final **Security checks**
job requires every security job to succeed. Skipped jobs, installation errors
and missing reports also fail it. To block merges on this result, make the
check required in GitHub's branch protection settings.

| Check | Scope and failure behavior |
| --- | --- |
| CPAN::Audit / CPANSA::DB | Installs runtime, recommended, test and author dependencies on Perl 5.44; audits all installed CPAN distributions, the interpreter, and declared dependency constraints. Any advisory or scanner error fails the job. |
| Gitleaks 8.30.1 | Scans the complete checked-out Git history, including earlier commits, without printing secret values. Findings fail the job. |
| actionlint 1.7.12 | Checks workflow structure, expressions and embedded shell scripts. |
| zizmor 1.31.1 | Checks workflow permissions, expression injection, credential persistence and action pinning in offline mode. |
| Perl::Critic security policies | Rejects string eval, two-argument open, bareword file handles and backtick shell execution in library, maintainer scripts, examples and Makefile.PL. |

Before the declared-constraints scan, CPAN::Meta and Module::CPANfile convert
the generated `MYMETA.json` prerequisites into a temporary `cpanfile`, the
input format supported by `cpan-audit deps`. This preserves phase and relation
constraints, including optional PDL. Missing/invalid metadata stops the job.
`maint/audit-dependencies.pl` retains the unmodified scanner result under
`stock_report` in each JSON artifact and gates the corrected report. Scanner
errors from either report fail the job. Advisory matching still uses CPAN::Audit
and the current CPANSA::DB; there is no advisory exclusion mechanism.

The adapter corrects two independently reproduced discovery problems in
CPAN::Audit 20261013.002. Installed package declarations with a version, such as
`package Pod::Man v6.1.1;`, are parsed statically with PPI without executing
the module or its version expressions. The scoped substitution preserves the scanner's installed-file
traversal and CoreList fallback. Declared phases and requires/recommends relations
are audited separately, so optional or author minima cannot hide vulnerable
versions still allowed for runtime consumers. Requirements mapping to the same
distribution within one scope are intersected. Perl's explicit minimum is
kept separate from zero-version core-module requirements; a nonzero core-module
or non-main-module version that cannot be mapped safely fails with an error.
The declared scan queries only distributions actually declared, rather than
adding unrelated modules from the runner's CoreList. Database mapping gaps
are recorded under each scope's `unmapped_modules`, never described as a safety result.
Unsupported relation types fail instead of being silently discarded.

The generated manifest is retained with the CVE JSON artifacts for 14 days.
Redacted Gitleaks JSON is retained for 7 days. Artifacts are attempted even after scanner failure. Scanner and
advisory database versions appear in job logs. No `continue-on-error`,
`--exit-zero`, vulnerability exclusion file or secret allowlist is configured.
The existing malformed-WAV, resource-limit, I/O-failure and lifecycle tests
remain in the ordinary test matrix.

## Pipeline and update policy

All actions are pinned to complete commit SHAs. Checkouts do not persist Git
credentials. Jobs have read-only repository access; the aggregate gate has no
permissions. Security checks use the normal pull-request event, without
privileged `pull_request_target`, repository secrets, or write tokens. Timeouts
bound every job. Gitleaks and actionlint are built from pinned Go module
versions using Go's checksum verification; zizmor is installed at a pinned
version in a temporary virtual environment (Python 3.11+ is required).
CPAN::Audit and CPANSA::DB deliberately update to the latest available release
on each run rather than freeze the vulnerability feed.

Dependabot checks pinned GitHub Actions weekly. Routine version updates have
a seven-day cooldown; GitHub documents that cooldown does not apply to
security updates. Review the pinned CLI scanner versions periodically; they
are not automatically updated by the GitHub Actions ecosystem integration.
CPAN auditing is separate from Dependabot because CPAN is not covered by
that ecosystem configuration.

## Limits and responses

A CVE match needs an applicability review: version, vendor patches and input
conditions. Perl advisories may require an interpreter upgrade. This audit
runs on Perl 5.44; it does not scan the older interpreters in the test matrix.

Coverage depends on the database's advisories and module-to-distribution
mappings. PDL had no entry in the database used on 2026-10-24, so this audit
could not assess it. Tool and network failures must remain failures.

CodeQL does not support Perl source. Perl::Critic provides targeted source
checks, not full taint/dataflow analysis. zizmor runs without GitHub API access;
API-dependent checks such as commit provenance cannot be established offline.
Secrets found in history require credential rotation and exposure review,
even after removal from the current source.

Any future exception needs an exact advisory/fingerprint, evidence explaining
why it does not apply, an owner and an expiry/review date. Do not add broad
exclusions to make the pipeline green.

## Remote results, 2026-10-25

[Security run 40187441825](https://github.com/gipidevdor/ham-rtty/actions/runs/40187441825)
completed on source `85eb8f3fce614d30cb53eaeb0da6b978dbc3dacc`.
The aggregate gate failed. Complete-history secret scanning, Perl unsafe
construct checks and workflow syntax/security checks passed. Installed and
declared dependency audits both failed, with no scanner errors.

CPAN::Audit 20261013.002 with CPANSA::DB 20261018.001 reported two installed
matches (File::Temp and Perl) and 38 unique declared distribution/advisory
matches: 29 Perl, three Encode, three Storable, two PathTools and one File::Temp.
Applicability to Ham::RTTY remains unresolved. No advisory exclusion was added.

The [verification record](verification.md) distinguishes this remote source
from the documentation working tree. The [raw summary](current-results.json)
retains tool/database metadata, scopes, advisory IDs, job outcomes and SHA-256
hashes of the original audit artifacts. Full reports remain CI artifacts
subject to the configured 14-day retention. Historical local observations
below are not a fresh audit of the developer's environment.

## Historical local verification, 2026-10-24

actionlint 1.7.12 and zizmor 1.31.1 accept both workflows and Dependabot config.
Gitleaks 8.30.1 found no leaks in 21 commits or the local directory scan; output
was redacted. All four targeted Perl::Critic policies passed. Negative controls
confirmed that a synthetic credential is rejected with a redacted report, and
invalid/unsafe workflow fixtures make actionlint and zizmor exit nonzero.
Distribution metadata validation also passed.

CPAN::Audit 20260622.001 with CPANSA::DB 20260923.001 reported three advisory
matches in the local developer environment: CPANSA-perl-2026-15534,
CPANSA-File-Temp-2011-4116 and CPANSA-podlators-2026-82560. The installed
environment audit exits nonzero. The initial declared scan did not discover
Makefile.PL prerequisites; the corrected scan now consumes generated cpanfile
metadata. Its round-trip check preserves all phases/relations and PDL 2.081.
Unlike installed-version matches, a constraint scan can report historical
vulnerable versions permitted by broad lower bounds; its matches need
separate review. No exclusions were added. These are
local database matches awaiting applicability review, not validated Ham::RTTY
vulnerabilities or results from the GitHub runner. The initial remote workflow also reported three installed-version matches and
67 declared-range matches. Later investigation reproduced the discovery
problems described above. These historical counts are retained as baseline
evidence, not current adapter results.

## Corrective prerequisites

The build/configure minimum is ExtUtils::MakeMaker 7.22, excluding the earlier
current-directory module-search issue. Author prerequisites now require
Archive::Tar >=3.10 (covering known archive extraction/allocation issues),
Perl::Tidy >=20260826, Pod::Man >=v6.1.1 and PPI >=1.291.
Archive utilities enforce their minimum at startup; the package parser
uses static tokens instead of evaluating version assignments. Security CI explicitly installs
the fixed podlators release before auditing. These are author/build updates;
the default runtime still uses the same core modules and supports Perl 5.20.
File::Temp's advisory has no fixed version in this database, and updating tools
does not patch the interpreter. Remaining matches must continue to fail the gate.

`xt/security-audit.t` supplies vulnerable and fixed package versions, a downgrade,
merged phase requirements, core aliases and unsupported metadata. It requires
vulnerable versions to remain red and fixed versions to clear their advisory.

## Historical corrective local results, 2026-10-24

With CPAN::Audit 20261013.002 and CPANSA::DB 20261018.001, the corrected
installed audit reports two matches (File::Temp and Perl), compared with three
in its retained stock report. Fixed podlators v6.1.1 is inventoried correctly.
The corrected declared audit reports 38 unique distribution/advisory matches;
its stock counterpart reports 57 after the prerequisite updates (the original
baseline was 67). It retains 29 Perl, three Encode, three Storable, two PathTools
and one File::Temp match. Both corrected audits still exit nonzero, with no
scanner errors. This progress does not constitute a clean security gate.

The declared report retains phase/relation/version scopes and deduplicates
only repeated occurrences of the same distribution/advisory. It does not
let author/recommended upgrades erase weaker runtime requirements. Remaining
legacy-version matches and the two installed matches still need remediation
or a source-backed applicability decision; no exception is configured.

## Run the checks locally

Use a disposable Perl environment to install the full dependency set and the
current CPAN::Audit/CPANSA::DB before interpreting results. The commands retain
nonzero exit status when advisories or errors occur:

```sh
cpan-audit --version
perl maint/audit-dependencies.pl installed
task_audit_dir=$(mktemp -d)
perl -MCPAN::Meta -MModule::CPANfile -e 'my $meta = CPAN::Meta->load_file("MYMETA.json"); print Module::CPANfile->from_prereqs($meta->prereqs)->to_string' > "$task_audit_dir/cpanfile"
perl maint/audit-dependencies.pl declared MYMETA.json "$task_audit_dir"
gitleaks git --redact=100
actionlint
zizmor --offline --no-progress .github
for policy in ProhibitStringyEval ProhibitTwoArgOpen ProhibitBarewordFileHandles ProhibitBacktickOperators; do
    perlcritic --single-policy "$policy" lib maint examples Makefile.PL || exit 1
done
```

## Tool references

- [CPAN::Audit commands and exit codes](https://metacpan.org/pod/cpan-audit)
- [Gitleaks](https://github.com/gitleaks/gitleaks)
- [zizmor usage and offline limitations](https://docs.zizmor.sh/usage/)
- [actionlint](https://github.com/rhysd/actionlint)
- [Dependabot cooldown](https://docs.github.com/en/code-security/reference/supply-chain-security/dependabot-options-reference#cooldown)
- [CodeQL supported languages](https://codeql.github.com/docs/codeql-overview/supported-languages-and-frameworks/)
