# Free reception examples: credits and licences

These files retain their source licences. The project's Artistic 2.0 licence
does not replace the recording terms. Credits do not imply endorsement.

## DWD recordings

`dwd-france-day.wav`, `dwd-france-afternoon.wav` and `dwd-uk-morning.wav`
are excerpts of **DWD Hamburg RTTY weather DDH7**, recorded and published by
**NIL HEARD / Reception Log**, under
[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).
The unchanged [legal text](CC-BY-4.0.txt) includes the warranty disclaimer.

| Distributed file | Source capture | Receiver | Excerpt |
| --- | --- | --- | --- |
| `dwd-france-day.wav` | [2026-10-06 11:59:53 UTC](https://nilheard.com/capture/2026-10-06T1159Z-7644.5-rtty-7646/) | PRADIERS DEP 15 JN15LG, FRANCE | 0–30 seconds |
| `dwd-france-afternoon.wav` | [2026-10-05 13:51:37 UTC](https://nilheard.com/capture/2026-10-05T1351Z-7644.5-rtty-7646/) | Montmorillon 86500 FRANCE | 30–60 seconds |
| `dwd-uk-morning.wav` | [2026-10-03 09:51:11 UTC](https://nilheard.com/capture/2026-10-03T0951Z-7644.5-rtty-7646/) | Wessex - KiwiSDR - G8JNJ - South West UK | 30–60 seconds |

Changes: losslessly published FLAC decoded, resampled to 8000 Hz, converted to
16-bit mono PCM WAV, and trimmed as listed. No denoising or synthetic signal
was added. Weather transmission: Deutscher Wetterdienst (DWD); the excerpts
contain station identification, frequency announcements and test sequences.
The archive's [rights statement](https://nilheard.com/about/) and individual
capture pages identify the recording licence. Its published WAV hashes refer
to upstream originals; separately measured download hashes identify the FLAC
files actually used. Both are recorded in [the inventory](../free.json).

## Amateur recording

`amateur-contest.wav` is an excerpt of
[RTTY on 3587.0kHz.wav](https://freesound.org/people/Bryce835/sounds/608805/)
by **Bryce835**, published 2021-11-16 under
[CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/).
The unchanged [legal text](CC0-1.0.txt) is included.

Changes: Freesound's public HQ MP3 preview decoded, resampled to 8000 Hz,
converted to 16-bit mono PCM WAV and trimmed to its first 20 seconds.
The original uploaded WAV was not used. The source describes amateur contest
reception; the transmitted exchanges contain callsigns and numeric reports.
The actual capture timestamp is not supplied by the source and is unknown.

## External generated signal

`wikipedia-generated.wav` derives from
[RTTY.ogg](https://commons.wikimedia.org/wiki/File:RTTY.ogg), originally by
**Mysid**, with the current replacement uploaded by **Idahoprogrammer** on
2017-03-10. The file page dedicates the work to the public domain worldwide,
with an unrestricted-use fallback where a public-domain release is not
possible. The licence identifier `LicenseRef-Public-Domain` refers to that
specific declaration, not to CC0.

Changes: the current Ogg Vorbis file decoded and converted to 8000-Hz mono
16-bit PCM WAV, without trimming. It was generated externally using gMFSK;
it is **not an off-air recording**.

## Reproduction and review

[The inventory](../free.json) records download URLs, exact SHA-256 values,
transformations, decoder commands, licence links and review date. SoX 14.4.2
performed format conversion; minimodem 0.24 supplied independent decoder
outputs. Neither program is bundled or required by the library or offline tests.
Licence texts are copied unchanged from Creative Commons' official
[legal tools repository](https://github.com/creativecommons/cc-legal-tools-data).

The independent outputs are not authoritative transcripts. Their errors have
not been silently corrected. These examples do not satisfy the separately
reviewed field-CER release gate in [real.json](../real.json).
