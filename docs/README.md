# Documentation

[Project](../README.md) · [Task guide](usage.md) · [Examples](../examples/README.md)

[Read online](https://gipidevdor.github.io/ham-rtty/).

| Task | Guide |
| --- | --- |
| Install or check your environment | [Installation](installing.md) |
| Convert text, make files or receive RTTY | [Task guide](usage.md#command-line-use) |
| Resolve an error or warning | [Recovery guide](usage.md#when-you-need-help) |
| Use the library in an application | [Library recipes](usage.md#library-recipes) |
| Run an API example | [Example catalog](../examples/README.md#choose-a-path) |
| Choose an API or representation | [Interfaces](usage.md#choose-an-interface) and [data representations](usage.md#choose-the-data-representation) |
| Understand timing, state and filtering | [Architecture](architecture.md) |
| Understand detector thresholds | [Power heuristics](architecture.md#detector-power-heuristics) |
| Compare backend speed | [Measured performance](benchmarks.md) |
| Try a licensed radio recording | [Free reception examples](../corpus/free/README.md) |
| Review tests and recordings | [Verification](verification.md) and [reference corpus](../corpus/README.md) |
| Change or release the project | [Contributing](../CONTRIBUTING.md) and [release procedure](releasing.md) |
| Review dependencies or security | [Dependency decisions](dependency-audit.md), [security CI](security-ci.md) and [reporting](../SECURITY.md) |

## Installed reference

Use `perldoc Ham::RTTY` for the library and `perldoc ham-rtty` for the command.
From a checkout, use `perldoc lib/Ham/RTTY.pm` or `perldoc bin/ham-rtty`.

## Reading measurements

Measurements are tied to a source revision and date.
[Benchmark results](performance-results.json), [coverage](coverage-results.json)
and the [verification record](verification.md) retain the measured observations.

Project code uses [Artistic License 2.0](../LICENSE). Recording-specific terms,
attribution and transformations are listed in [NOTICE](../NOTICE) and
[recording licenses](../corpus/real/LICENSES.md).
