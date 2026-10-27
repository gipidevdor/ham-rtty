# Reporting a security issue

For a suspected vulnerability involving untrusted WAV/MIDI/event input,
use the repository's private vulnerability reporting form:

[Report a vulnerability privately](https://github.com/gipidevdor/ham-rtty/security/advisories/new)

Include the affected version, a minimal input or reproduction and the
observed impact. Avoid attaching private radio traffic or credentials.
Use public issues for ordinary correctness and DSP limitations.

The library processes local input and has no runtime networking. File-size,
frame and event limits are part of its defensive boundary. Only the current
development version receives fixes; no response-time guarantee is offered.

## Automated checks

Pull requests, main-branch changes and weekly scheduled runs check known
CPAN/Perl advisories, committed secrets, workflow security and unsafe Perl
constructs. Reports and limitations are described in
[Security CI](docs/security-ci.md). Any advisory or scanner failure fails
the final `Security checks` gate. This is not a guarantee of absence of bugs.
