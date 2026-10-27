# Dependency audit

[Overview](../README.md) · [Security CI](security-ci.md)

The default runtime uses Perl core modules available with Perl 5.20.
MakeMaker 7.22 or later is a build prerequisite. PDL 2.081 or later is optional;
explicit `pdl` requires it, `auto` falls back to Perl when unavailable.
There is no Ham::CW runtime dependency.

`Makefile.PL` declares runtime, test and development requirements separately.
Development tools include Perl::Tidy, Perl::Critic, Devel::Cover, POD/metadata
validators and documentation-site libraries. These are not library runtime
dependencies. [PDL](https://metacpan.org/pod/PDL) remains optional.

The security workflow audits both installed versions and declared constraints.
An unconstrained old supported version can match an advisory even when the
installed toolchain is newer. Matches require individual evidence and triage;
see [security CI](security-ci.md). No audit claim is inherited from another
project's measurements.
