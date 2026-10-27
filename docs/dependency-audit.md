# Dependency and namespace audit

[Overview](../README.md) · [Task guide](usage.md) · [Examples](../examples/README.md) · [Contributing](../CONTRIBUTING.md)

Dependency choices, based on [MetaCPAN](https://fastapi.metacpan.org/) metadata
checked on 2026-10-24. [Raw metadata](cpan-audit.json) records versions and
prerequisites. Third-party tests were inspected where noted, but not run.
For advisory results, see [security CI](security-ci.md).

| Candidate | Observed release | License / minimum Perl | Decision |
| --- | --- | --- | --- |
| [Text::Morse](https://metacpan.org/pod/Text::Morse) | 0.07, 2015-06-10 | Artistic 2.0; 5.6.1 | Ham::RTTY's internal codec handles its strict symbol policy, explicit prosigns and incremental events. |
| [Audio::Wav](https://metacpan.org/pod/Audio::Wav) | 0.14, 2014-04-27 | License/minimum Perl absent from release metadata | Ham::RTTY implements a bounded PCM subset with RIFF validation and structured errors. |
| [Audio::Data](https://metacpan.org/pod/Audio::Data) | Audio 1.029, 2004-06-02 | License/minimum Perl unknown | Not selected: native sample storage conflicts with the pure-Perl default backend. |
| [PDL](https://metacpan.org/pod/PDL) | 2.106, 2026-08-18 | Perl terms; 5.16 | Optional backend, selected with `backend => 'pdl'` or `auto`. See [measurements](benchmarks.md). |
| [Math::FFT](https://metacpan.org/pod/Math::FFT) | 1.36, 2020-10-17 | Perl terms; 5.8 | The narrow-band detector uses direct projections and does not need an FFT. |
| [MIDI](https://metacpan.org/pod/MIDI) | MIDI-Perl 0.84, 2023-10-17 | Perl terms in POD; release prerequisites unspecified | Ham::RTTY exports a bounded type-0 track with its own timing and error handling. General MIDI editing and device I/O are outside its scope. |

Text::Morse declares Test::Simple/Test::More as runtime requirements.
Audio::Wav declares no non-core runtime dependencies; Audio's metadata is too
sparse to resolve its tree. Math::FFT includes native code. PDL requires
File::Map and parsing/configuration modules; its optional scientific and device
facilities are not required by Ham::RTTY.

The JSON records direct prerequisites by phase. Full dependency trees, licenses
and platform builds were not audited for these candidates. No implementation
source was copied from them. The Artistic 2.0 license is reproduced verbatim.

## Names

On 2026-10-24, the [CPAN package index](https://www.cpan.org/modules/02packages.details.txt.gz)
and [public PAUSE permissions export](https://www.cpan.org/modules/06perms.txt.gz)
contained no `Ham::RTTY` or `Ham::RTTY::*` entries. The
[MetaCPAN module endpoint](https://fastapi.metacpan.org/v1/module/Ham::RTTY)
returned HTTP 404. Confirm upload permissions with the maintainer's PAUSE
account before publication; the public index does not reserve a namespace.

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
