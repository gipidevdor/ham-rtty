# Releasing

[Overview](../README.md) · [Verification](verification.md) · [Contributing](../CONTRIBUTING.md)

Version 0.01 is under development. Complete every required verification
check before tagging or publishing a release.

1. Run warnings-fatal tests on every supported CI platform and Perl version.
2. Run `make distmeta` and all author tests, including documentation, style,
   metadata, manifest, minimum version, spelling and corpus provenance.
3. Collect statement/branch/condition coverage with PDL installed. Require
   95% statements and 90% branches for every production module.
4. Run the real-reception corpus tool; missing fixtures must fail. Each clip
   needs clear redistribution rights, hashes, independent transcript, CER at
   most 25% and a measured regression budget.
5. Run three-iteration 8/16 kHz benchmarks sequentially, plus peak-RSS measurement
   for 120 seconds at 48 kHz through `read_wav`. Record environment and hashes.
6. Audit installed and declared dependencies; triage every match and require all
   security CI jobs. Check Pages build, local links and subpath rendering.
7. Update `Changes`, version, MANIFEST, raw results and verification together.
8. Build/test the archive and isolated installation:

```sh
perl Makefile.PL
make test
make distmeta
prove -lr xt
make distcheck
make disttest
make dist
perl maint/check-dist.pl Ham-RTTY-0.01.tar.gz
perl maint/check-install.pl Ham-RTTY-0.01.tar.gz
```

Review the exact candidate commit and hosted checks before tagging/publishing.
CPAN upload, remote push and public deployment are separate release actions.
