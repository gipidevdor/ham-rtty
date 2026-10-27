# Documentation

[Project](../README.md) · [Task guide](usage.md) · [Examples](../examples/README.md)

[Read online](https://gipidevdor.github.io/ham-rtty/).

| Task | Guide |
| --- | --- |
| Install or check your environment | [Installation](installing.md) |
| Convert text or inspect ITA2 codes | [Text and timing](usage.md#text-and-timing) |
| Make WAV or MIDI files | [Audio](usage.md#audio) and [file workflows](usage.md#files-and-command-line) |
| Receive audio incrementally | [Streaming](usage.md#streaming) |
| Run an API example | [Examples](../examples/README.md) |
| Understand timing, state and detection | [Architecture](architecture.md) |
| Review character mappings and attribution | [Standards and provenance](standards.md) |
| Compare backend speed | [Measured performance](benchmarks.md) |
| Review tests and recordings | [Verification](verification.md) and [reference corpus](../corpus/README.md) |
| Change or release the project | [Contributing](../CONTRIBUTING.md) and [release procedure](releasing.md) |
| Review dependencies or security | [Dependency decisions](dependency-audit.md), [security CI](security-ci.md) and [reporting](../SECURITY.md) |

## Installed reference

Use `perldoc Ham::RTTY` for the library and `perldoc ham-rtty` for the command.
From a checkout, use `perldoc lib/Ham/RTTY.pm` or `perldoc bin/ham-rtty`.

## Reading measurements

Measurements are tied to a source revision and date. The
[verification record](verification.md), [coverage results](coverage-results.json)
and [benchmark results](performance-results.json) retain the measured evidence.
Unverified recordings and incomplete release gates are identified explicitly.

Copyright © 2026 Giacomo Picchiarelli. Project code and original material use
[Artistic License 2.0](../LICENSE). Attribution and recording admission rules
are listed in [NOTICE](../NOTICE) and [recording licenses](../corpus/real/LICENSES.md).
