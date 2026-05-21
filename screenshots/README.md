# Screenshots

This directory holds evidence screenshots referenced by the [attack walkthroughs](../attacks/) and the [pentest write-up](../writeup/writeup.md). Images are intentionally not committed yet — the walkthroughs contain placeholders so the documentation reads cleanly before a live run, and you drop real captures in here as you execute the lab.

## Naming convention

```
attack-<N>-step-<M>.png
```

| Token | Meaning | Example |
|-------|---------|---------|
| `<N>` | Attack number, matching the file in [../attacks/](../attacks/) (`01`–`10`, written without leading zero in the filename) | `attack-2-step-3.png` → step 3 of [02-kerberoasting.md](../attacks/02-kerberoasting.md) |
| `<M>` | Step number within that attack's **Step-by-step Commands** section | |

### Attack-number map

| N | Walkthrough | MITRE |
|---|-------------|-------|
| 1 | [BloodHound Enumeration](../attacks/01-bloodhound-enumeration.md) | T1087.002 |
| 2 | [Kerberoasting](../attacks/02-kerberoasting.md) | T1558.003 |
| 3 | [AS-REP Roasting](../attacks/03-asrep-roasting.md) | T1558.004 |
| 4 | [NTLM Relay](../attacks/04-ntlm-relay.md) | T1557.001 |
| 5 | [Pass-the-Hash](../attacks/05-pass-the-hash.md) | T1550.002 |
| 6 | [DCSync](../attacks/06-dcsync.md) | T1003.006 |
| 7 | [Golden Ticket](../attacks/07-golden-ticket.md) | T1558.001 |
| 8 | [Silver Ticket](../attacks/08-silver-ticket.md) | T1558.002 |
| 9 | [Unconstrained Delegation](../attacks/09-unconstrained-delegation.md) | T1550.003 |
| 10 | [Cross-Forest Trust Abuse](../attacks/10-cross-forest-trust-abuse.md) | T1134.005 |

## Capture guidelines

- **Resolution:** capture at native resolution; crop to the relevant window. Target ≤ 1920 px wide.
- **Format:** PNG (lossless, sharp text). Convert to optimized PNG before committing to keep repo size down.
- **Redaction:** this is a throwaway lab using `Password123!`, so no real secrets exist — but still scrub anything host-specific (your real hostname, public IPs) before publishing to a portfolio.
- **Consistency:** prefer a dark terminal theme with a legible monospace font so screenshots read well at thumbnail size on GitHub.

## Why screenshots are git-ignored selectively

[`.gitignore`](../.gitignore) keeps temp/scratch files out (`*.tmp`, `~$*`) but lets committed `.png` evidence through. This `README.md` and `.gitkeep` ensure the directory exists in a fresh clone.

---
Last updated: 2026-05-17
MITRE ATT&CK: <https://attack.mitre.org/>
