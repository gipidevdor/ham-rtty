# Dependency and namespace audit

[Overview](../README.md) · [Task guide](usage.md) · [Examples](../examples/README.md) · [Contributing](../CONTRIBUTING.md)

The default backend implements the codec, bounded PCM subset and narrowband
detector in this distribution. It needs no external audio programs or device
APIs. [PDL](https://metacpan.org/pod/PDL) is optional; see [measurements](benchmarks.md).
For advisory results, see [security CI](security-ci.md).

## Names

Confirm CPAN indexing and PAUSE permissions with the maintainer's account
before publication. The repository name does not reserve a CPAN namespace;
no authenticated namespace-permission check is recorded for this candidate.

## Runtime footprint

Only core modules are required: Carp, Exporter, Hash::Util, Scalar::Util,
Storable, Fcntl, File::Basename, File::Temp, Encode, Getopt::Long, IO::Handle
JSON::PP and Text::Wrap, plus strict/warnings and Perl itself.
File::Temp provides safe replacement output and bounded seekable WAV stdin.
Test::More is a test requirement. Corpus hash verification also requires
Digest::SHA 5.96 or later for tests, excluding its historical CVE-2016-1238
range; older Perls may need that test module upgraded separately.
ExtUtils::MakeMaker 7.22 or later is required at configure time. It installs
the library, executable, manual and Windows launcher, and excludes the older
current-directory module-search vulnerability.
Perl::Critic, Perl::Tidy, Devel::Cover and metadata/POD checkers are author-only.
PDL 2.081 or later is an optional runtime recommendation. Local verification
used PDL 2.106 and its required dependencies, excluding optional scientific
and device modules.
