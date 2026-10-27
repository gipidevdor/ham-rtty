# Ham::RTTY

Ham::RTTY converts text to Morse, generates WAV and MIDI files, and decodes
recorded CW. Use it through the Perl API or the `ham-rtty` command.

Requires Perl 5.20 or later. The default backend uses core modules; PDL is
optional. Audio reception is experimental.

[Online documentation](https://gipidevdor.github.io/ham-rtty/) ·
[Guides](docs/README.md) · [Examples](examples/README.md) ·
[API reference](lib/Ham/RTTY.pm) · [Contributing](CONTRIBUTING.md)

## Start here

Run from a checkout without installing:

```sh
perl -Ilib bin/ham-rtty encode "CQ TEST"
perl -Ilib bin/ham-rtty decode -- "-.-. --.- / - . ... -"
```

These commands convert `CQ TEST` to Morse and back. Spaces separate letters;
`/` separates words. Use `--` before Morse that starts with a dash.

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
ham-rtty wav --wpm 20 --effective-wpm 12 --output practice.wav "CQ TEST"
ham-rtty receive --frequency 700 --wpm 20 --effective-wpm 12 practice.wav
```

This creates a 20 WPM recording with 12 WPM Farnsworth spacing, then reads it
with matching tone and speed hints. Add `--overwrite` to replace an existing file.

| You want to… | Command |
| --- | --- |
| Convert text | `ham-rtty encode "CQ TEST"` |
| Read Morse | `ham-rtty decode -- "... --- ..."` |
| Inspect timing | `ham-rtty events "SOS"` |
| Export MIDI | `ham-rtty midi --output practice.mid "CQ TEST"` |
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

my $cw = Ham::RTTY->new(wpm => 20, frequency => 700);
print $cw->encode('SOS'), "\n";
print $cw->decode('... --- ...'), "\n";

my $result = $cw->decode_wav_bytes(
    $cw->wav_bytes('SOS'), frequency => 700, wpm => 20);
print $result->text, "\n";
for my $warning (@{$result->warnings}) {
    warn "$warning->{code}: $warning->{message}\n";
}
```

More recipes: [task guide](docs/usage.md#library-recipes) and
[examples](examples/README.md). Read the API with `perldoc Ham::RTTY`, or
`perldoc lib/Ham/RTTY.pm` from a checkout.

## Know what to expect

Morse symbols follow ITU-R M.1677-1. Write prosigns as tokens such as `<AR>`
and quote them in the shell. The [symbol table](docs/usage.md#symbol-policy)
lists the accepted characters and tokens.

The receiver can separate CW signals on distinct tones. Interference, fading
and uncertain timing can still produce partial or incorrect text. Check its
warnings; `--strict` returns a nonzero status when warnings occur. See
[reception limits](docs/usage.md#practical-limits) and [test results](docs/verification.md).

Playback, microphone capture and radio or MIDI device control are left to the
calling application.

## Explore the project

[Documentation](docs/README.md) · [Contributing](CONTRIBUTING.md) ·
[Release procedure](docs/releasing.md) · [Security reports](SECURITY.md)

[Security audit](docs/security-ci.md): Perl/File::Temp advisories and older dependency versions remain under review.

Copyright © 2026 Giacomo Picchiarelli. Project code and original material use
[Artistic License 2.0](LICENSE). Third-party audio retains its CC0 or CC BY-SA
3.0 terms; see [NOTICE](NOTICE) and [recording licenses](corpus/real/LICENSES.md).
