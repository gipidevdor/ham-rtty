# Real radio recordings: sources, licenses and preparation

These recordings are separate third-party corpus material. Their audio licenses
below apply to the WAV derivatives; the library's Artistic License does not
replace those terms. Sources and licenses were checked on 2026-10-24 using each
Commons file's own metadata, not the site's general page license.

| Derivative | Author | Source | Audio license |
| --- | --- | --- | --- |
| `4u1un.wav` | Cqdx | [4U1UN beacon](https://commons.wikimedia.org/wiki/File:4U1UN_beacon.ogg) | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) |
| `oh2b.wav` | Cqdx | [NCDXF beacons](https://commons.wikimedia.org/wiki/File:NCDXF_beacons.ogg) | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) |
| `cs3b.wav` | Cqdx | [NCDXF beacons](https://commons.wikimedia.org/wiki/File:NCDXF_beacons.ogg) | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) |
| `sk6rud.wav` | HBD20 | [SK6RUD](https://commons.wikimedia.org/wiki/File:SK6RUD.ogg) | [CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0/) |

SK6RUD's derivative remains CC BY-SA 3.0: retain attribution, the license link
and the indication of changes when redistributing it; adaptations of that audio
are subject to the same license. All authors are credited above even where CC0
does not require attribution. The source descriptions identify received beacon
signals; these are not recordings of this project's oscillator.

The original uploader credits each source as their own work. The checked
source-page revisions and exact license metadata are retained in
[license-evidence.json](license-evidence.json). Original media SHA-1 values
were compared with the downloaded source files; derivative SHA-256 values
are checked in the suite. The source pages do not list additional restrictions.

Full legal texts are included as [CC0-1.0.txt](CC0-1.0.txt) and
[CC-BY-SA-3.0.txt](CC-BY-SA-3.0.txt). Keep this attribution notice, the per-file
metadata, source links, change descriptions and applicable audio license when
redistributing the corpus. [NOTICE](../../NOTICE) identifies the exceptions
to the project's code license.

Every derivative was prepared from the retained source Ogg bytes, after
checking their original SHA-256: decode Ogg/Vorbis, average channels,
resample the complete recording to 8000 Hz with `scipy.signal.resample_poly`,
crop the stated interval, then write signed 16-bit mono PCM. No denoising or
gain adjustment was applied. The 4U1UN crop keeps its original interval and
contains the identification before the calibration carriers; the other three
crops were later shortened to the complete callsigns. Python soundfile and
SciPy were preparation tools only; running the tests needs neither.
`../real.json` records the source URLs, source/derivative SHA-256 hashes,
intervals, transformations and transcript references, and
`license-evidence.json` retains the preparation tool versions.

| Clip | Source interval (s) | Reference | WPM hint |
| --- | ---: | --- | ---: |
| 4U1UN | 0–3.5 | `4U1UN` | 20 |
| OH2B | 1.84–4.66 | `OH2B` | 22 |
| CS3B | 11.85–14.46 | `CS3B` | 22 |
| SK6RUD | 1.95–7 | `SK6RUD` | 17 |

Intervals were annotated from independent raw tone projections and the known
Morse groups, rather than selected by searching decoder CER. The first S in
SK6RUD starts at approximately 1.95 seconds of this source, after the partly
cut `DE`; this crop excludes that prefix. OH2B and CS3B keep the complete
callsigns and stop before the first calibration carrier (about 5.0 and 14.79
seconds respectively). Two-second crops would truncate these references:
51 and 47 Morse units at the NCDXF controller's nominal 54 ms dot require
about 2.75 and 2.54 seconds before margins. See the
[NCDXF timing specification](https://www.ncdxf.org/beacon/beaconcontroller.html).

Transcript identity comes from the source descriptions and corpus review,
not from Ham::RTTY output. Speed hints are evaluation parameters; matching text
does not establish exact speed estimation or general off-air accuracy.
The corpus is small, uses automated beacon keying and does not establish
manual-keying or conversational-QSO accuracy.

CER is Levenshtein edit distance divided by reference character count, with
insertions, deletions, substitutions, spaces and replacement characters all
counted. It may exceed 100%, and transcripts are not normalized.
`max_regression_cer_hinted` and `max_regression_cer_estimated` record separate
measured budgets for decoding with the stated speed and with no WPM hint.
The unassisted run also uses the automatic bandwidth default.
`max_regression_cer` retains the hinted baseline for compatibility;
`quality_target_cer` remains independently fixed at 0.25. Historical results
on the longer NCDXF intervals and the SK6RUD reference without its leading
prefix are not directly comparable to the corrected crops. Run
`perl maint/reception-corpus.pl` for measured text, errors and warnings.

The real-audio test and reporting script run both speed modes for every clip.
The test prints both CERs on one note line and validates the reporting columns.
The report keeps `cer` for the hinted result and adds explicit `cer_hinted`,
`cer_estimated`, `text_estimated`, `estimated_wpm` and estimated-mode warnings/frequency.
These are separate runs, not copies of the hinted output. Matching text does
not certify accurate estimated speed or reception on other recordings.
