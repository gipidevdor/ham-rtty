# Ham::RTTY

Ham::RTTY converts text to ITA2 codes, generates AFSK WAV and MIDI files, and
decodes recorded RTTY. Use it through the Perl API or the `ham-rtty` command.

Requires Perl 5.20 or later. The default backend uses core modules; PDL is
optional. Audio reception is experimental.

[Online documentation](https://gipidevdor.github.io/ham-rtty/) ·
[Guides](docs/README.md) · [Examples](examples/README.md) ·
[API reference](lib/Ham/RTTY.pm) · [Contributing](CONTRIBUTING.md)

## Start here

Run from a checkout without installing:

```sh
perl -Ilib bin/ham-rtty encode "CQ TEST"
perl -Ilib bin/ham-rtty decode "[LTRS] 01110 10111 00100 10000 00001 00101 10000"
```

These commands convert `CQ TEST` to ITA2 codes and back. Spaces separate
five-bit numeric codes; `[FIGS]` and `[LTRS]` select figures and letters.

To install from a checkout or extracted distribution:

```sh
perl Makefile.PL
make
make test
make install
```

Builds require ExtUtils::MakeMaker 7.22 or later and your Perl's make program.
See [installation](docs/installing.md) for user-owned paths and upgrades.
Once installed, run `ham-rtty` directly.

## Make a practice recording

```sh
ham-rtty wav --baud 50 --shift 450 --output practice.wav "CQ TEST"
ham-rtty receive --mark 2125 --baud 50 --shift 450 practice.wav
```

This creates a 50-baud recording with 450 Hz shift, then reads it with matching
tones and speed. Add `--overwrite` to replace an existing file.

Try the [free reception recordings](corpus/free/README.md) for real radio
examples with matching settings and their own licence notices.

| You want to… | Command |
| --- | --- |
| Convert text | `ham-rtty encode "CQ TEST"` |
| Read ITA2 codes | `ham-rtty decode "[LTRS] 00011"` |
| Inspect transmitted bits | `ham-rtty bits "CQ TEST"` |
| Inspect timing | `ham-rtty events "CQ TEST"` |
| Export debug MIDI | `ham-rtty midi --output practice.mid "CQ TEST"` |
| Inspect a recording and its warnings | `ham-rtty receive --json recording.wav` |
| Find options for one task | `ham-rtty help receive` |

Text commands accept `--input FILE` or stdin. Use `--output FILE` to save
text or JSON. WAV and MIDI require an explicit output; `--output -` selects
binary stdout. Prefer named binary files in Windows shells.

Use `ham-rtty help COMMAND` for options and examples, or the
[recovery guide](docs/usage.md#when-you-need-help) for errors and reception warnings.

## Use it in Perl

Save as `demo.pl` and run `perl -Ilib demo.pl` from this checkout,
or `perl demo.pl` after installation:

```perl
use 5.020;
use strict;
use warnings;
use Ham::RTTY;

my $rtty = Ham::RTTY->new(baud => 50, mark => 2125, shift => 450);
print $rtty->encode('CQ TEST'), "\n";
print $rtty->decode('[LTRS] 00011'), "\n";

my $result = $rtty->decode_wav_bytes(
    $rtty->wav_bytes('CQ TEST'), mark => 2125, baud => 50, shift => 450);
print $result->text, "\n";
for my $warning (@{$result->warnings}) {
    warn "$warning->{code}: $warning->{message}\n";
}
```

For long audio, use the [memory-conscious file and streaming paths](docs/usage.md#memory-conscious-operation).

More recipes: [task guide](docs/usage.md#library-recipes) and
[examples](examples/README.md).
Read the API with `perldoc Ham::RTTY`, or `perldoc lib/Ham/RTTY.pm` from a checkout.

## Know what to expect

The international character table follows ITU-T S.1. A separate `us` profile
provides US TTY figures; USOS is configurable at both ends. See
[character policy](docs/usage.md#text-and-timing) and
[standards and provenance](docs/standards.md).

Defaults are 45.45 baud, 2125 Hz MARK, +170 Hz SPACE, 1.5 stop bits and USOS
on. AFSK phase remains continuous across tone transitions. Logical bit strings
round a 1.5-bit stop up to two digits; frames and events preserve its timing.

The receiver needs configured baud. It does not identify baud or shift
automatically, separate simultaneous stations, equalise or combine diversity
channels. Interference and fading can still produce partial or incorrect text.
Check warnings; `--strict` returns a nonzero status when warnings occur. See
[reception settings](docs/usage.md#streaming) and [test results](docs/verification.md).

Version 0.001 is under development. Real-recording validation, dependency
review and remaining platform checks must pass before release. See the
[verification record](docs/verification.md) for results and open items.

Playback, microphone capture and radio or MIDI device control are left to the
calling application. MIDI is a two-note visual/debug rendering.

## Explore the project

[Documentation](docs/README.md) · [Contributing](CONTRIBUTING.md) ·
[Release procedure](docs/releasing.md) · [Security reports](SECURITY.md)

[Security audit](docs/security-ci.md): Perl/File::Temp advisories and older
dependency versions remain under review.

Copyright © 2026 Giacomo Picchiarelli. Project code and original material use
[Artistic License 2.0](LICENSE). The [free reception examples](corpus/free/README.md)
retain their own licences; see [NOTICE](NOTICE) and
[recording credits](corpus/free/LICENSES.md).
