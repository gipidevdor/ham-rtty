# Standards and provenance

[Overview](../README.md) · [Usage](usage.md) · [Verification](verification.md)

## Normative character mapping

The `ita2` profile implements the repertoire and code-element mapping of
[ITU-T S.1 (03/93)](https://www.itu.int/rec/T-REC-S.1-199303-I/en), Table 1.
The ITU catalogue lists that edition as in force (checked 2026-10-27).
The distribution includes the codec and numeric test vectors. The ITU
publication, diagrams and table artwork are not bundled; obtain the
recommendation from its publisher.

| Source provision | Implementation and evidence |
| --- | --- |
| §§2–3: repertoire and five-unit code | Baudot tables; `t/02-standards.t` contains independent numeric vectors |
| §3 / Table 1: element 1 transmitted first | Encoder frames emit numeric bit 0 first; known A vector is `11000` |
| §4.1: WRU in figures D position | U+0005 is the library representation; no answerback hardware action |
| §4.2: national figures F/G/H | Unassigned in `ita2`; strict encoding rejects undefined national signs |
| §4.3: audible signal | U+0007 in figures J; no automatic audible action |
| §4.4: shifts and initial shift | Each nonempty encoded message begins with LTRS or FIGS |
| §4.5: NULL/shift movement | Shifts produce no text; NULL is preserved as U+0000 for an explicit data API |

ASCII apostrophe and hyphen represent the corresponding printed signs.
Lowercase ASCII is normalized to uppercase; no Unicode transliteration occurs.

## Separate operating profiles

`us` is a separately named US TTY figures profile. Its exact differences are
listed in [usage](usage.md#text-and-timing) and Baudot POD. It does not claim
to be the ITU international figures table. USOS is a receiver/transmitter
interoperability option for amateur practice, separate from the S.1 mapping.

Baud rate, start/stop duration, AFSK frequencies, shift and USB/LSB settings are
explicit signal parameters. S.1 defines the character code; transmitter
hardware, occupied bandwidth and radio operation require separate assessment.
The library has no device-control interface.

## Software and recording licences

Code and documentation use [Artistic License 2.0](../LICENSE). The author's
reference-project components are attributed in [NOTICE](../NOTICE), including
the unchanged documentation style and adapted WAV/I/O machinery. Optional
PDL and development tools remain separately licensed dependencies, not
vendored source. Runtime uses Perl core modules; no Ham::CW runtime dependency.

Five external examples are distributed in [the free corpus](../corpus/free/README.md):
three CC BY 4.0 DWD recording excerpts, one CC0 1.0 amateur excerpt and one
externally generated signal with its source's public-domain dedication.
[Per-file credits and terms](../corpus/free/LICENSES.md) retain authors, source
links, modifications and licence texts; [the inventory](../corpus/free.json)
retains original/derivative hashes and reproduction commands. The project's
Artistic 2.0 licence does not replace those terms or grant rights to third-party
transmissions. Credits do not imply endorsement.

The four independently annotated release-quality recordings remain missing.
Admission to that separate [release corpus](../corpus/real/LICENSES.md) requires
explicit redistribution/adaptation rights, source/author, legal evidence,
original and derivative hashes, transformations and an independent transcript.
Public access to a stream alone is insufficient evidence of permission.
Synthetic oscillator output is never labelled off-air evidence.

## Build tools and distribution boundary

CI actions, operating-system packages, cpanminus and optional PDL retain their
upstream licences. They are separate tools/dependencies, not copied into the
Ham::RTTY runtime or relicensed under Artistic 2.0. The supplementary CI tool
licences and exact upstream revisions are listed in
[portability](portability.md#tool-licences). The standalone cpanminus script and
VM images are fetched only on CI runners; `.github` workflows are excluded
from the CPAN archive by `MANIFEST.SKIP`. No source from `nicomen/perl-matrix`
is copied or called.

This distinction depends on the actual files shipped. Bundling an action,
installer, interpreter, native library or container image would need a fresh
licence review of that material and its dependencies. The CI setup is not a
permission to redistribute those components under the project's licence.
