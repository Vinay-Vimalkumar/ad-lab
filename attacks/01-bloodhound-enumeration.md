# 01 — BloodHound Enumeration (T1087.002)

Before any targeted attack, an operator maps the directory: who can log on where, which accounts hold dangerous privileges, and which Access Control List (ACL) misconfigurations create a path to Domain Admins. This walkthrough collects the `sevenkingdoms.local` forest with two collectors (the C# SharpHound CE collector from `braavos`, and the Python `bloodhound-python` collector from the Linux attacker), imports the data into BloodHound CE 6.x, and runs cypher queries that surface the deliberately-planted privilege escalation paths.

**MITRE ATT&CK Technique**: [T1087.002 — Account Discovery: Domain Account](https://attack.mitre.org/techniques/T1087/002/)

## Prerequisites
- Any valid domain credential in `sevenkingdoms.local` (a low-privileged user is enough — this lab uses `braavos\arya.stark` / domain user `arya.stark`).
- Network reachability to the forest root DC `kingslanding` (192.168.56.10, LDAP/389, LDAPS/636, Global Catalog 3268) and the child DC `winterfell` (192.168.56.12).
- For the Windows collector: a domain-joined or domain-context session on `braavos` (192.168.56.14).
- For anonymous LDAP enumeration: nothing — this lab leaves anonymous LDAP bind enabled on `kingslanding`.

## Tools
- SharpHound CE collector (ships with BloodHound CE 6.x) — run on `braavos`.
- `bloodhound-python` (BloodHound.py, compatible with BloodHound CE 6.x) — run on the Linux attacker.
- BloodHound CE 6.x (web UI + Neo4j backend) — run on the Linux attacker.
- Impacket v0.12.0 (`ldapsearch`-style checks / supporting enum).

## Step-by-step Commands

### Step 1 — (Linux attacker, 192.168.56.1) Confirm anonymous LDAP enumeration is possible
This lab intentionally permits an anonymous bind. Use it to confirm the naming context before authenticating.
```bash
ldapsearch -x -H ldap://{{DC_IP}} -s base -b "" namingContexts
# {{DC_IP}} = 192.168.56.10 (kingslanding)
```

### Step 2 — (braavos, 192.168.56.14) Run the SharpHound CE collector against the whole forest
Open an elevated PowerShell as a domain user. `-c All` runs every collection method; `--zipfilename` controls the output archive name.
```powershell
# {{LAB_PASSWORD}} = Password123!  (only needed if launching as another user via runas)
cd C:\Tools\SharpHound
.\SharpHound.exe -c All -d {{DOMAIN}} --domaincontroller 192.168.56.10 --zipfilename sevenkingdoms_collect
# {{DOMAIN}} = sevenkingdoms.local
```

### Step 3 — (Linux attacker, 192.168.56.1) Alternative collection with bloodhound-python
Run the Python collector when you only have credentials and no Windows host. Collect both domains in the forest.
```bash
bloodhound-python -u arya.stark -p '{{LAB_PASSWORD}}' \
  -d sevenkingdoms.local -dc kingslanding.sevenkingdoms.local \
  -ns {{DC_IP}} -c All --zip
# Repeat for the child domain:
bloodhound-python -u arya.stark -p '{{LAB_PASSWORD}}' \
  -d north.sevenkingdoms.local -dc winterfell.north.sevenkingdoms.local \
  -ns 192.168.56.12 -c All --zip
```

![Step 1](../screenshots/attack-1-step-1.png)

### Step 4 — (Linux attacker, 192.168.56.1) Start BloodHound CE and import the data
```bash
# Bring up the BloodHound CE stack (Neo4j + API + UI)
docker compose -f bloodhound-ce/docker-compose.yml up -d
# UI: http://localhost:8080  — then Administration > File Ingest > Upload the .zip archives
```
Upload the SharpHound archive (`*_sevenkingdoms_collect.zip`) and both `bloodhound-python` `.zip` files.

![Step 4](../screenshots/attack-1-step-4.png)

### Step 5 — (BloodHound CE UI) Run the privilege-path cypher queries
Shortest path from an owned principal to Domain Admins:
```cypher
MATCH p=shortestPath((u:User {name:"ARYA.STARK@SEVENKINGDOMS.LOCAL"})-[*1..]->(g:Group {name:"DOMAIN ADMINS@SEVENKINGDOMS.LOCAL"}))
RETURN p
```
Find all Kerberoastable accounts (users with an SPN):
```cypher
MATCH (u:User) WHERE u.hasspn = true
RETURN u.name, u.serviceprincipalnames
```
Surface the planted ACL abuse edges:
```cypher
MATCH p=(s)-[r:GenericWrite|WriteDacl|ForceChangePassword]->(t)
RETURN s.name, type(r), t.name
```

![Step 5](../screenshots/attack-1-step-5.png)

## Expected Output

Anonymous LDAP bind (Step 1):
```text
# extended LDIF
dn:
namingContexts: DC=sevenkingdoms,DC=local
namingContexts: CN=Configuration,DC=sevenkingdoms,DC=local
namingContexts: CN=Schema,CN=Configuration,DC=sevenkingdoms,DC=local
namingContexts: DC=DomainDnsZones,DC=sevenkingdoms,DC=local
namingContexts: DC=ForestDnsZones,DC=sevenkingdoms,DC=local
```

SharpHound CE collector (Step 2):
```text
2026-05-17T10:42:18.114-05:00|INFORMATION|This version of SharpHound is compatible with the 6.x Release of BloodHound
2026-05-17T10:42:18.661-05:00|INFORMATION|Initializing SharpHound at 10:42 AM on 5/17/2026
2026-05-17T10:42:19.402-05:00|INFORMATION|Loaded cache with stats: 0 ID to type mappings.
2026-05-17T10:42:20.118-05:00|INFORMATION|Beginning LDAP search for sevenkingdoms.local
2026-05-17T10:43:02.555-05:00|INFORMATION|Status: 412 objects finished (+412 9.81/s) -- Using 78 MB RAM
2026-05-17T10:43:03.901-05:00|INFORMATION|Enumeration finished in 00:00:43.7829112
2026-05-17T10:43:04.221-05:00|INFORMATION|Saving cache with stats: 388 ID to type mappings.
2026-05-17T10:43:04.460-05:00|INFORMATION|SharpHound Enumeration Completed at 10:43 AM on 5/17/2026!
2026-05-17T10:43:04.460-05:00|INFORMATION|Output saved to 20260517104304_sevenkingdoms_collect.zip
```

bloodhound-python (Step 3):
```text
INFO: Found AD domain: sevenkingdoms.local
INFO: Connecting to LDAP server: kingslanding.sevenkingdoms.local
INFO: Found 1 domains
INFO: Found 2 domains in the forest
INFO: Found 18 computers
INFO: Found 41 users
INFO: Found 9 groups
INFO: Found 4 trusts
INFO: Done in 00M 22S
INFO: Compressing output into 20260517104410_bloodhound.zip
```

Kerberoastable query result (Step 5):
```text
u.name                              u.serviceprincipalnames
SVC_MSSQL@SEVENKINGDOMS.LOCAL       ["MSSQLSvc/sql01.sevenkingdoms.local:1433"]
SVC_WEB@SEVENKINGDOMS.LOCAL         ["HTTP/web01.sevenkingdoms.local"]
SVC_CIFS@SEVENKINGDOMS.LOCAL        ["CIFS/fileserver.sevenkingdoms.local"]
SVC_LDAP@NORTH.SEVENKINGDOMS.LOCAL  ["LDAP/app01.north.sevenkingdoms.local"]
```

ACL abuse edges (Step 5):
```text
s.name                                  type(r)               t.name
HR@SEVENKINGDOMS.LOCAL                  GenericWrite          FINANCE@SEVENKINGDOMS.LOCAL
SERVICEACCOUNTS@SEVENKINGDOMS.LOCAL     WriteDacl             TYWIN.LANNISTER@SEVENKINGDOMS.LOCAL
AUTHENTICATED USERS@SEVENKINGDOMS.LOCAL ForceChangePassword   SANSA.STARK@SEVENKINGDOMS.LOCAL
```

## Cleanup Steps
- On `braavos`: delete the collector archive and cache — `Remove-Item C:\Tools\SharpHound\*_sevenkingdoms_collect.zip, C:\Tools\SharpHound\*.bin`.
- On the Linux attacker: `rm -f *_bloodhound.zip` and tear down the stack with `docker compose -f bloodhound-ce/docker-compose.yml down -v` (the `-v` purges the Neo4j volume so collected directory data is not retained).
- Clear the BloodHound database from the UI (Administration > Database Management > Clear Database) if you keep the stack running.
- No accounts or objects were modified — enumeration is read-only, so no directory rollback is required.

## What This Tells You About AD
Active Directory is a graph, not a list. Every user, computer, group, and ACL is an edge, and attackers think in terms of reachable paths rather than individual permissions. The planted findings — `HR` holding `GenericWrite` over `Finance`, `ServiceAccounts` with `WriteDacl` over a Domain Admin (`tywin.lannister`), and `Authenticated Users` able to `ForceChangePassword` on `sansa.stark` — are each individually "just a delegated permission," but chained together they form a route from any authenticated user to forest compromise. The defensive lesson is that least-privilege must be evaluated transitively: audit ACLs the way BloodHound does, prune `WriteDacl`/`GenericWrite`/`ForceChangePassword` grants over privileged objects, disable anonymous LDAP bind, and treat the existence of an exploitable path — not just the presence of an admin login — as the risk.

## Detection Reference
See [../detection/kql-queries.md#1-bloodhound-enumeration](../detection/kql-queries.md#1-bloodhound-enumeration) for the high-volume LDAP query and SharpHound collection signatures (Directory Services 1644, sustained LDAP page reads, anomalous Global Catalog binds).

---
Last updated: 2026-05-17

MITRE references:
- [T1087.002 — Account Discovery: Domain Account](https://attack.mitre.org/techniques/T1087/002/)
- [TA0007 — Discovery](https://attack.mitre.org/tactics/TA0007/)
