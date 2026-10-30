# Portability

[Overview](../README.md) · [Installation](installing.md) · [Verification](verification.md)

The [supplementary workflow](https://github.com/gipidevdor/ham-rtty/blob/main/.github/workflows/portability.yml) builds and tests
the distribution on FreeBSD 14.5, FreeBSD 15.1 and 64-bit Cygwin. It runs on
pull requests, pushes to main and manual dispatch. These jobs extend the existing
Linux, macOS and native Windows matrix; the five PDL configurations remain there.
Solaris and additional Perl versions are not added in this expansion.

## What is checked

Each environment installs declared build/test dependencies, checks Perl is at
least 5.20, runs `perl Makefile.PL`, `make` and warnings-fatal `make test`, then
executes the example catalog and verifies the installed CLI. Installation uses
a prefix containing a space to exercise path handling. The job logs retain test
outcomes; an artifact records `uname` and the complete `perl -V` configuration.
PDL is optional and is not explicitly installed in these supplementary jobs.
A passing pure-Perl job does not establish PDL support on the same platform.

FreeBSD runs in a virtual machine with the release selected explicitly.
Cygwin runs its own Perl and shell on the Windows runner, separately from the
existing Strawberry Perl jobs. Source line endings remain LF. Each job has a
30-minute limit and failures remain visible; no `continue-on-error` is used.

## Workflow dependencies

The workflow is written for this repository. The external workflow
[nicomen/perl-matrix](https://github.com/nicomen/perl-matrix) was evaluated as a
reference; its source is not copied or invoked. Runtime dependencies and the
Artistic 2.0 distribution licence are unchanged.

The VM action is [vmactions/freebsd-vm v1.5.9](https://github.com/vmactions/freebsd-vm/tree/c46abacb49f09938ca4e1702d15d836285d694cc),
and setup uses [cygwin/cygwin-install-action v7](https://github.com/cygwin/cygwin-install-action/tree/5a1b0cd107181fa6bb6bf3f90d500f4fb3132f18).
All actions use full commit pins. Checkout credentials are not retained and
workflow permissions are read-only. FreeBSD packages supply cpanminus; Cygwin
fetches the upstream standalone cpanminus 1.7049 from commit
`99cef089c7fc3188a19822f594515dbd5295b855` and verifies SHA-256
`137e8c5856e09867f6d7631d6d67a5e7778166962e29830c573cbbbab6ed2e21`
before execution. These tools execute only in CI and are not bundled in the
Perl distribution. Package repositories and VM images remain external inputs;
recorded environment details describe each observed run.

FreeBSD versions were selected from the project's
[supported releases](https://www.freebsd.org/security/#sup) on 2026-10-30.
A configured job is not a passing result; hosted outcomes are recorded after
its first run. Existing dependency-audit and real-recording release gates
remain mandatory.
