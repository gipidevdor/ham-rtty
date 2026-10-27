# Reception corpus

[Overview](../README.md) · [Licensing](real/LICENSES.md)

[Free reception examples](free/README.md) include four licensed off-air excerpts
and one external generated signal, with independent decoder comparisons.
They run offline and retain their own [licence notices](free/LICENSES.md).

The synthetic suite includes independent S.1 frames in `t/06-robustness.t`,
full generator/receiver matrix tests, noise and mismatch cases. Synthetic audio
is not an off-air recording and is not counted as field evidence.

Four real RTTY recordings are required: three 50-baud/450-Hz weather-service
clips and one 45.45-baud/170-Hz amateur clip. Their reviewed inventory is
[real.json](real.json). Entries identify the still-missing independently annotated release fixtures.
The free examples have independent decoder output, not authoritative transcripts;
no field CER or release regression budgets have been fabricated.

`perl maint/reception-corpus.pl` fails loudly if any fixture or its provenance
is missing. Real-audio acceptance remains a release gate. Public WebSDR access
alone does not grant redistribution rights. Each admitted recording needs
source, author, explicit licence, transformations, SHA-256 and an independently
annotated transcript. CER is Levenshtein distance divided by reference length,
including spaces and controls; no transcript normalization is implicit.
