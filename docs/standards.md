# Standards and provenance

[Overview](../README.md) · [Usage](usage.md) · [Verification](verification.md)

## Normative character mapping

The `ita2` profile implements the repertoire and code-element mapping of
[ITU-T S.1 (03/93)](https://www.itu.int/rec/T-REC-S.1-199303-I/en), Table 1.
The ITU catalogue lists that edition as in force (checked 2026-10-27).
The implementation is an independently written codec, not a copy of ITU prose,
PDF, diagrams or table artwork. ITU publication copyright is not replaced by
the software licence; obtain the recommendation from its publisher.

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
A successful software test is not independent certification by ITU.

## Separate operating profiles

`us` is a separately named US TTY figures profile. Its exact differences are
listed in [usage](usage.md#text-and-timing) and Baudot POD. It does not claim
to be the ITU international figures table. USOS is a receiver/transmitter
interoperability option requested for amateur practice, not an S.1 requirement.

Baud rate, start/stop duration, AFSK frequencies, shift and USB/LSB settings are
explicit signal parameters. This project tests those requested contracts;
S.1 alone does not certify a radio transmitter, spectrum allocation, occupied
bandwidth or authorization to transmit. Device control is outside the library.
No universal legal or equipment certification is claimed by this distribution.

## Software and recording licences

Code and documentation use [Artistic License 2.0](../LICENSE). The author's
reference-project components are attributed in [NOTICE](../NOTICE), including
the unchanged documentation style and adapted WAV/I/O machinery. Optional
PDL and development tools remain separately licensed dependencies, not
vendored source. Runtime uses Perl core modules; no Ham::CW runtime dependency.

No third-party radio recording is currently distributed. Admission requires
explicit redistribution/adaptation rights, source/author, legal evidence,
original and derivative hashes, transformations and an independent transcript.
See [recording licences](../corpus/real/LICENSES.md). Public access to a stream
alone is insufficient evidence of permission. Missing fixtures block release;
synthetic oscillator output is never labelled off-air evidence.
