# Examples

[Overview](../README.md) · [Task guide](../docs/usage.md)

Run these programs with `perl -Ilib` from a checkout or use the installed library.
Output files must be new; these examples protect existing destinations.

| Program | Purpose |
| --- | --- |
| [send.pl](send.pl) | Save text as continuous-phase AFSK WAV |
| [receive.pl](receive.pl) | Receive a WAV at the configured 45.45 baud |
| [midi.pl](midi.pl) | Save two-note debug MIDI |
| [workflows.pl](workflows.pl) | WAV round trip in memory |
| [text-events.pl](text-events.pl) | Notation and exact timed events |
| [run-all.pl](run-all.pl) | Installed backend smoke test |

```sh
perl -Ilib examples/send.pl cq.wav CQ TEST
perl -Ilib examples/receive.pl cq.wav
perl -Ilib examples/midi.pl cq.mid CQ TEST
perl -Ilib examples/workflows.pl
perl -Ilib examples/run-all.pl --backend perl
```
