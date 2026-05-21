# Attack 03 Detection Verification

Query target: `kingslanding` (`192.168.56.10`) Security log.

Query method: Ansible WinRM from `ansible-control`, filtering Security Event ID `4768` from the last two hours and selecting events where `PreAuthType` is `0`.

Result: detected.

Matching events:

| TimeCreated UTC | Event ID | TargetUserName | IpAddress | TicketEncryptionType | PreAuthType |
|---|---:|---|---|---|---:|
| 2026-05-21T04:44:06.5700373+00:00 | 4768 | sansa.stark | ::ffff:192.168.56.20 | 0x12 | 0 |
| 2026-05-21T04:44:06.5676181+00:00 | 4768 | arya.stark | ::ffff:192.168.56.20 | 0x12 | 0 |
| 2026-05-21T04:44:06.5650571+00:00 | 4768 | jon.snow | ::ffff:192.168.56.20 | 0x12 | 0 |

Raw log: `logs/phase3-attack03-detection.log`
