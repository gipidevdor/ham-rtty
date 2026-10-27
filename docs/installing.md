# Installation

[Documentation](README.md) · [Overview](../README.md) · [Task guide](usage.md)

## Requirements

Requires Perl 5.20 or later and ExtUtils::MakeMaker 7.22 or later.
CPAN clients install the required MakeMaker automatically. For a manual build,
upgrade an older copy with `cpanm ExtUtils::MakeMaker` first.

## Build and install

From an extracted distribution or repository root:

```sh
perl Makefile.PL
make
make test
make install
```

Use the make program supplied with your Perl installation (`gmake` on some
Windows installations). The final command needs write permission to Perl's
library directory. For a user-owned destination, configure with
`perl Makefile.PL INSTALL_BASE=/your/install/directory` and include its
`lib/perl5` directory in `PERL5LIB` when running applications.

To use a checkout without installing, run `perl -Ilib script.pl` from the
repository root. The CPAN distribution is `Ham-RTTY`; the Perl package is `Ham::RTTY`.

## Verify the installation

```sh
ham-rtty --version
ham-rtty encode "SOS"
perldoc Ham::RTTY
```

The conversion prints `... --- ...`. If the command is not found, check that
Perl's installation `bin` directory is on `PATH`. For a checkout, use
`perl -Ilib bin/ham-rtty --version` from the repository root.
