# Microsoft Sentinel KQL Detection Catalog — Active Directory Attack Lab

This catalog provides one production-style **Microsoft Sentinel KQL** detection per attack
technique exercised in the lab. Each entry names the query, declares its log source, gives a
syntactically valid and runnable KQL query, maps to MITRE ATT&CK, and documents the expected
match count under lab conditions, realistic false-positive scenarios, and production tuning
guidance.

All queries assume the standard Sentinel/Log Analytics schema:

- **SecurityEvent** — Windows Security audit log forwarded via the Azure Monitor Agent (AMA)
  Data Collection Rule. Used for Kerberos (4768/4769), logon (4624/4625), special-privilege
  (4672), directory-access (4662/4661), and share-access (5145) events.
- **Sysmon** — System Monitor events ingested via AMA into the `Event` table
  (`Source == "Microsoft-Windows-Sysmon"`). EventIDs: 1 process create, 3 network connect,
  10 process access (LSASS), 11 file create, 22 DNS query.
- **DeviceProcessEvents / DeviceNetworkEvents / IdentityLogonEvents** — Microsoft Defender
  for Endpoint / Defender for Identity advanced-hunting tables (Entra-joined estate).

> **Log Source Onboarding.** The Sysmon configuration and detection-as-code Sigma rules that
> feed these queries are Codex-owned and live alongside this file in the `detection/` directory:
> [`sysmon-config.xml`](./sysmon-config.xml) (Sysmon operational config — process, network,
> image-load, and LSASS-access logging) and [`sigma-rules/`](./sigma-rules/) (vendor-neutral
> Sigma source that compiles to these KQL detections). Onboard SecurityEvent via an AMA Data
> Collection Rule scoped to the Domain Controllers OU, and forward Sysmon `Operational` channel
> events through the same DCR. Do not edit those files from here — they are referenced only.

Per-attack walkthroughs (prerequisites, execution, and artifacts) live in
[`../attacks/`](../attacks/): see
[01-bloodhound-enumeration.md](../attacks/01-bloodhound-enumeration.md),
[02-kerberoasting.md](../attacks/02-kerberoasting.md),
[03-asrep-roasting.md](../attacks/03-asrep-roasting.md),
[04-ntlm-relay.md](../attacks/04-ntlm-relay.md), and
[05-pass-the-hash.md](../attacks/05-pass-the-hash.md).

## Table of Contents

1. [BloodHound Enumeration](#1-bloodhound-enumeration) — T1087.002
2. [Kerberoasting](#2-kerberoasting) — T1558.003
3. [AS-REP Roasting](#3-as-rep-roasting) — T1558.004
4. [NTLM Relay](#4-ntlm-relay) — T1557.001
5. [Pass-the-Hash](#5-pass-the-hash) — T1550.002
6. [DCSync](#6-dcsync) — T1003.006
7. [Golden Ticket](#7-golden-ticket) — T1558.001
8. [Silver Ticket](#8-silver-ticket) — T1558.002
9. [Unconstrained Delegation Abuse](#9-unconstrained-delegation-abuse) — T1550.003 / T1187
10. [Cross-Forest Trust Abuse](#10-cross-forest-trust-abuse) — T1134.005 / T1558.001

---

## 1. BloodHound Enumeration

**Query name: `BloodHound / SharpHound Bulk Directory Enumeration`**

**Log source:** SecurityEvent (Windows Directory Service access, EventID 4662) with a Sysmon
(`Event` table, EventID 3) corroboration query. SharpHound generates a high-volume burst of
directory-object reads from a single host in a short window.

```kql
// Primary: bulk 4662 directory-object reads from one account in a short window
let lookback = 1h;
let burstWindow = 10m;
let objectThreshold = 200;   // distinct objects read per account per bin
SecurityEvent
| where TimeGenerated > ago(lookback)
| where EventID == 4662
| where AccessMask has_any ("0x100", "0x10")   // ControlAccess / ReadProperty
| where ObjectServer == "DS"
| extend Actor = tolower(SubjectUserName)
| where Actor !endswith "$"                      // exclude machine accounts (tuned below)
| summarize
        DistinctObjects = dcount(ObjectName),
        SampleObjects   = make_set(ObjectName, 25),
        SourceHosts     = make_set(Computer, 10),
        FirstSeen       = min(TimeGenerated),
        LastSeen        = max(TimeGenerated)
    by Actor, bin(TimeGenerated, burstWindow)
| where DistinctObjects > objectThreshold
| project TimeGenerated, Actor, DistinctObjects, SourceHosts, SampleObjects, FirstSeen, LastSeen
| order by DistinctObjects desc
```

```kql
// Corroboration: SharpHound process / collector network fan-out via Sysmon
Event
| where TimeGenerated > ago(1h)
| where Source == "Microsoft-Windows-Sysmon"
| where EventID == 3
| extend ed = parse_xml(EventData)
| extend Image = tostring(ed.DataItem.EventData.Data[4]["#text"]),
         DestPort = toint(tostring(ed.DataItem.EventData.Data[14]["#text"]))
| where DestPort in (389, 636, 3268, 3269)        // LDAP / LDAPS / Global Catalog
| summarize LdapConnections = count(), DistinctDestPorts = dcount(DestPort) by Computer, Image, bin(TimeGenerated, 5m)
| where LdapConnections > 50
| order by LdapConnections desc
```

- **MITRE technique mapping:** [T1087.002 — Account Discovery: Domain Account](https://attack.mitre.org/techniques/T1087/002/) (related: [T1018](https://attack.mitre.org/techniques/T1018/), [T1069.002](https://attack.mitre.org/techniques/T1069/002/))
- **Expected match count under lab conditions:** 1–2 hits (a single SharpHound `All`/`DCOnly`
  run produces one dominant burst row per collecting account, well above the 200-object
  threshold; the Sysmon query yields 1 row for the collector host).
- **False positive scenarios:** vulnerability scanners (Tenable/Nessus AD audit, Qualys),
  Active Directory health tooling (PingCastle, Purple Knight, ADRecon), Azure AD Connect sync
  account enumeration, and identity-governance products that crawl the directory on a schedule.
- **Production tuning guidance:** baseline normal per-account `dcount(ObjectName)` over 14–30
  days and set `objectThreshold` to p99 + margin; allowlist scanner and sync service accounts
  via a Sentinel watchlist (`join kind=leftanti` against `_GetWatchlist('TrustedEnumApps')`);
  keep machine-account exclusion but review tier-0 service accounts separately; alert on the
  *combination* of the 4662 burst and the LDAP fan-out for higher fidelity.

---

## 2. Kerberoasting

**Query name: `Kerberoasting — RC4 Service Ticket Requests (4769)`**

**Log source:** SecurityEvent (Kerberos Service Ticket Operations, EventID 4769).

```kql
let lookback = 24h;
let spnThreshold = 3;   // distinct service SPNs requested per account
SecurityEvent
| where TimeGenerated > ago(lookback)
| where EventID == 4769
| where TicketEncryptionType == "0x17"                 // RC4-HMAC (downgrade signal)
| where TicketOptions == "0x40810000"                  // forwardable/renewable/canonicalize
| where ServiceName !endswith "$"                       // exclude computer-account SPNs
| where ServiceName != "krbtgt"
| where TargetUserName !endswith "$"
| extend Requestor = tolower(TargetUserName), ClientIP = tostring(IpAddress)
| summarize
        DistinctSPNs = dcount(ServiceName),
        SPNs         = make_set(ServiceName, 50),
        Tickets      = count(),
        SourceIPs    = make_set(ClientIP, 10),
        FirstSeen    = min(TimeGenerated),
        LastSeen     = max(TimeGenerated)
    by Requestor, bin(TimeGenerated, 1h)
| where DistinctSPNs >= spnThreshold
| project TimeGenerated, Requestor, DistinctSPNs, SPNs, Tickets, SourceIPs, FirstSeen, LastSeen
| order by DistinctSPNs desc
```

- **MITRE technique mapping:** [T1558.003 — Steal or Forge Kerberos Tickets: Kerberoasting](https://attack.mitre.org/techniques/T1558/003/)
- **Expected match count under lab conditions:** 1 alert row covering 3–4 SPNs (one per
  kerberoastable service account seeded in the lab — e.g. `MSSQLSvc`, `HTTP/web`, `svc_backup`).
- **False positive scenarios:** legacy applications that still negotiate RC4 (older SQL Server,
  pre-2016 service accounts), interop with non-Windows Kerberos clients, and account-migration
  windows. A single RC4 4769 is normal noise; the multi-SPN burst is the signal.
- **Production tuning guidance:** prioritize accounts with weak/long-lived passwords by joining
  to a watchlist of high-value SPNs; raise `spnThreshold` in large estates and bin to a tighter
  window (10–15m) to catch tooling bursts while suppressing slow legit RC4; track AES adoption
  and alert specifically when `0x17` is requested for an account that normally uses AES
  (`0x11`/`0x12`).

---

## 3. AS-REP Roasting

**Query name: `AS-REP Roasting — Pre-Auth-Disabled TGT Requests (4768)`**

**Log source:** SecurityEvent (Kerberos Authentication Service, EventID 4768).

```kql
let lookback = 24h;
SecurityEvent
| where TimeGenerated > ago(lookback)
| where EventID == 4768
| where PreAuthType == "0"                        // pre-authentication NOT required
| where TicketEncryptionType in ("0x17", "0x18")  // RC4 / AES roastable material
| where TargetUserName !endswith "$"
| extend Account = tolower(TargetUserName), ClientIP = tostring(IpAddress)
| summarize
        TgtRequests   = count(),
        DistinctAccts = dcount(Account),
        Accounts      = make_set(Account, 50),
        SourceIPs     = make_set(ClientIP, 10),
        FirstSeen     = min(TimeGenerated),
        LastSeen      = max(TimeGenerated)
    by ClientIP, bin(TimeGenerated, 30m)
| where DistinctAccts >= 1
| project TimeGenerated, ClientIP, DistinctAccts, Accounts, TgtRequests, SourceIPs, FirstSeen, LastSeen
| order by DistinctAccts desc
```

- **MITRE technique mapping:** [T1558.004 — Steal or Forge Kerberos Tickets: AS-REP Roasting](https://attack.mitre.org/techniques/T1558/004/)
- **Expected match count under lab conditions:** 1–2 rows (the lab seeds 1–2 accounts with
  `DONT_REQ_PREAUTH`; a single `Rubeus asreproast` / `GetNPUsers.py` run produces 4768
  PreAuthType 0 events for each).
- **False positive scenarios:** accounts legitimately configured with pre-authentication
  disabled for legacy Unix/Kerberos interop, smart-card edge cases, and certain appliance
  service accounts. These produce steady low-volume PreAuthType 0 traffic.
- **Production tuning guidance:** maintain an allowlist watchlist of accounts that *must* have
  pre-auth disabled and `join kind=leftanti`; alert hardest when a single source IP requests
  PreAuthType 0 TGTs for *multiple* accounts (enumeration pattern); pair with a daily inventory
  query of `DONT_REQ_PREAUTH` accounts from Defender for Identity to catch new misconfigurations
  at the source.

---

## 4. NTLM Relay

**Query name: `NTLM Relay — Coerced Auth Replayed to a Second Host`**

**Log source:** SecurityEvent (logon EventID 4624 NTLM, network logon type 3) correlated with
Sysmon network connections. Relay manifests as an NTLM network logon whose source IP is the
relay box rather than the genuine principal's workstation.

```kql
let lookback = 1h;
SecurityEvent
| where TimeGenerated > ago(lookback)
| where EventID == 4624
| where LogonType == 3                              // network logon
| where AuthenticationPackageName == "NTLM"
| where TargetUserName !endswith "$"
| extend Account = tolower(TargetUserName), SrcIP = tostring(IpAddress)
| where isnotempty(SrcIP) and SrcIP !in ("-", "127.0.0.1", "::1")
| summarize
        DistinctTargets = dcount(Computer),
        Targets         = make_set(Computer, 20),
        Logons          = count(),
        Accounts        = make_set(Account, 20),
        FirstSeen       = min(TimeGenerated),
        LastSeen        = max(TimeGenerated)
    by SrcIP, bin(TimeGenerated, 10m)
| where DistinctTargets >= 2 or Logons >= 10        // one source fanning NTLM to many hosts
| project TimeGenerated, SrcIP, DistinctTargets, Targets, Accounts, Logons, FirstSeen, LastSeen
| order by DistinctTargets desc
```

- **MITRE technique mapping:** [T1557.001 — Adversary-in-the-Middle: LLMNR/NBT-NS Poisoning and SMB Relay](https://attack.mitre.org/techniques/T1557/001/)
- **Expected match count under lab conditions:** 1 row — the `ntlmrelayx`/`Responder` host
  appears as a single `SrcIP` authenticating with NTLM to 2+ relayed targets within one bin.
- **False positive scenarios:** legacy applications and appliances that still use NTLM
  (scanners, MFPs, backup proxies, older line-of-business apps), VDI/RDS broker hosts that
  proxy many NTLM sessions, and load balancers presenting a shared source IP.
- **Production tuning guidance:** allowlist known NTLM-dependent service hosts via watchlist;
  alert on NTLM where Kerberos is expected (e.g. domain-joined client to a host with an SPN);
  enable and ingest **Defender for Identity** NTLM-relay analytics for protocol-level fidelity;
  drive NTLM auditing (Event 8004 / Restrict NTLM) and migrate to channel binding + SMB signing
  to reduce the legitimate NTLM baseline.

---

## 5. Pass-the-Hash

**Query name: `Pass-the-Hash — NTLM Network Logon with Forged Credential Markers`**

**Log source:** SecurityEvent (logon EventID 4624) with Sysmon EventID 10 (LSASS access)
corroboration for the credential-theft phase.

```kql
let lookback = 6h;
SecurityEvent
| where TimeGenerated > ago(lookback)
| where EventID == 4624
| where LogonType in (3, 9)                          // network / NewCredentials (overpass/runas)
| where AuthenticationPackageName == "NTLM"
| where LogonProcessName has_any ("NtLmSsp", "seclogo")
| where TargetUserName !endswith "$"
| where TargetUserName !in~ ("ANONYMOUS LOGON", "SYSTEM", "LOCAL SERVICE", "NETWORK SERVICE")
| extend Account = tolower(TargetUserName), SrcIP = tostring(IpAddress)
| summarize
        Targets   = make_set(Computer, 20),
        DistinctTargets = dcount(Computer),
        Logons    = count(),
        SrcIPs    = make_set(SrcIP, 10),
        FirstSeen = min(TimeGenerated),
        LastSeen  = max(TimeGenerated)
    by Account, bin(TimeGenerated, 15m)
| where DistinctTargets >= 2
| project TimeGenerated, Account, DistinctTargets, Targets, SrcIPs, Logons, FirstSeen, LastSeen
| order by DistinctTargets desc
```

```kql
// Corroboration: LSASS credential access (Mimikatz sekurlsa) via Sysmon EID 10
Event
| where TimeGenerated > ago(6h)
| where Source == "Microsoft-Windows-Sysmon"
| where EventID == 10
| extend ed = parse_xml(EventData)
| extend TargetImage = tostring(ed.DataItem.EventData.Data[7]["#text"]),
         GrantedAccess = tostring(ed.DataItem.EventData.Data[5]["#text"]),
         SourceImage = tostring(ed.DataItem.EventData.Data[3]["#text"])
| where TargetImage endswith "lsass.exe"
| where GrantedAccess in~ ("0x1010", "0x1410", "0x1438", "0x143a", "0x1fffff")
| project TimeGenerated, Computer, SourceImage, TargetImage, GrantedAccess
| order by TimeGenerated desc
```

- **MITRE technique mapping:** [T1550.002 — Use Alternate Authentication Material: Pass the Hash](https://attack.mitre.org/techniques/T1550/002/)
- **Expected match count under lab conditions:** 1 row from the 4624 query (a single compromised
  account authenticating laterally to 2+ hosts with NTLM), plus 1+ LSASS-access rows on the host
  where the hash was harvested.
- **False positive scenarios:** legitimate NTLM in mixed environments, software inventory and
  patch tools that hop across hosts, vulnerability scanners performing authenticated checks, and
  EDR/AV agents that legitimately open LSASS handles (filter by trusted `SourceImage`).
- **Production tuning guidance:** baseline per-account lateral spread and trigger on
  `DistinctTargets` above the account's norm; correlate the 4624 fan-out with the LSASS-access
  query on the source host within a join window for high confidence; allowlist EDR/AV LSASS
  readers in the Sysmon config and watchlist; enforce Protected Users group + LSA protection so
  any residual PtH stands out.

---

## 6. DCSync

**Query name: `DCSync — Directory Replication Requested by Non-DC (4662)`**

**Log source:** SecurityEvent (Directory Service Access, EventID 4662) filtered on the
replication control-access GUIDs.

```kql
let lookback = 24h;
// DS-Replication-Get-Changes and -GetChangesAll extended-right GUIDs
let replGuids = dynamic([
    "1131f6aa-9c07-11d1-f79f-00c04fc2dcd2",   // DS-Replication-Get-Changes
    "1131f6ad-9c07-11d1-f79f-00c04fc2dcd2"    // DS-Replication-Get-Changes-All
]);
SecurityEvent
| where TimeGenerated > ago(lookback)
| where EventID == 4662
| where Properties has_any (replGuids)
| extend Actor = tolower(SubjectUserName)
| where Actor !endswith "$"                    // legit replication is DC machine accounts ($)
| where Actor !in~ ("msol_*", "anonymous logon")
| summarize
        ReplRequests = count(),
        GuidsSeen    = make_set(Properties, 5),
        SourceHosts  = make_set(Computer, 10),
        FirstSeen    = min(TimeGenerated),
        LastSeen     = max(TimeGenerated)
    by Actor, bin(TimeGenerated, 30m)
| project TimeGenerated, Actor, ReplRequests, SourceHosts, GuidsSeen, FirstSeen, LastSeen
| order by LastSeen desc
```

- **MITRE technique mapping:** [T1003.006 — OS Credential Dumping: DCSync](https://attack.mitre.org/techniques/T1003/006/)
- **Expected match count under lab conditions:** 1 row — the `mimikatz lsadump::dcsync` /
  `secretsdump.py` run replicates as a non-machine user account, which is the anomaly the
  machine-account exclusion surfaces.
- **False positive scenarios:** the Azure AD Connect / Entra Connect sync account
  (`MSOL_*` / `AAD_*`) which legitimately holds Get-Changes rights, third-party AD migration and
  password-sync tools (Quest, ADSelfService), and **DC promotion** where a new DC replicates.
- **Production tuning guidance:** allowlist the specific sync and migration accounts by SID via a
  watchlist (`join kind=leftanti`) rather than name patterns; the machine-account (`$`) exclusion
  removes normal inter-DC replication — never alert on `$` actors here; periodically audit which
  principals hold the two replication extended rights and alert when a *new* principal first
  appears in a 4662 with these GUIDs.

---

## 7. Golden Ticket

**Query name: `Golden Ticket — TGS Use Without Preceding TGT / krbtgt Anomalies`**

**Log source:** SecurityEvent (Kerberos 4769 service-ticket use and 4768 TGT issuance) with
4624/4672 logon corroboration. A forged TGT is minted offline, so service tickets (4769) appear
for a principal with **no matching TGT request (4768)**, often with anomalous lifetimes or RC4.

```kql
let lookback = 24h;
// Accounts that present TGS requests (4769) but never requested a TGT (4768) in the window
let tgtAccounts =
    SecurityEvent
    | where TimeGenerated > ago(lookback)
    | where EventID == 4768
    | extend Acct = tolower(TargetUserName)
    | distinct Acct;
SecurityEvent
| where TimeGenerated > ago(lookback)
| where EventID == 4769
| where ServiceName != "krbtgt"
| extend Acct = tolower(TargetUserName), ClientIP = tostring(IpAddress)
| where Acct !endswith "$"
| where Acct !in~ ("anonymous logon", "")
| where Acct !in (tgtAccounts)                  // TGS without any observed TGT issuance
| summarize
        TgsRequests = count(),
        Services    = make_set(ServiceName, 25),
        EncTypes    = make_set(TicketEncryptionType, 5),
        SourceIPs   = make_set(ClientIP, 10),
        FirstSeen   = min(TimeGenerated),
        LastSeen    = max(TimeGenerated)
    by Acct, bin(TimeGenerated, 1h)
| project TimeGenerated, Acct, TgsRequests, Services, EncTypes, SourceIPs, FirstSeen, LastSeen
| order by TgsRequests desc
```

- **MITRE technique mapping:** [T1558.001 — Steal or Forge Kerberos Tickets: Golden Ticket](https://attack.mitre.org/techniques/T1558/001/)
- **Expected match count under lab conditions:** 1 row — a `mimikatz kerberos::golden` ticket
  injected with `Rubeus ptt` lets the forged principal request TGS (4769) with no 4768, surfacing
  as a single anomalous account.
- **False positive scenarios:** ticket caching across the analysis window boundary (TGT requested
  just before `lookback`), clients that obtained TGTs on a different DC not yet ingested, and
  long-lived service sessions. Tighten/lengthen the window to reduce edge cases.
- **Production tuning guidance:** widen `lookback` to exceed the maximum TGT lifetime (e.g. 11h)
  so legitimate cached TGTs are captured and only truly orphaned TGS stand out; rotate the
  `krbtgt` password twice and alert on tickets whose issuance predates the rotation; ingest
  **Defender for Identity** which natively flags forged-PAC and golden-ticket usage; baseline
  per-account encryption types and flag RC4 where AES is expected.

---

## 8. Silver Ticket

**Query name: `Silver Ticket — Service Access Without KDC-Issued Ticket (4624/4634 no 4769)`**

**Log source:** SecurityEvent (logon 4624 + special-privilege 4672 on the target service host)
correlated against KDC service-ticket issuance (4769) on the DC. A silver ticket is forged for a
specific service, so the host shows a Kerberos logon for which the DC issued **no 4769**.

```kql
let lookback = 12h;
// Service tickets actually issued by the KDC (per account) — the legit set
let issuedTgs =
    SecurityEvent
    | where TimeGenerated > ago(lookback)
    | where EventID == 4769
    | extend Acct = tolower(TargetUserName)
    | distinct Acct;
SecurityEvent
| where TimeGenerated > ago(lookback)
| where EventID == 4624
| where LogonType in (3)                          // network logon to the targeted service
| where AuthenticationPackageName == "Kerberos"
| extend Acct = tolower(TargetUserName), SrcIP = tostring(IpAddress)
| where Acct !endswith "$"
| where Acct !in~ ("anonymous logon", "system", "")
| where Acct !in (issuedTgs)                       // Kerberos logon with no KDC-issued TGS
| summarize
        Logons    = count(),
        Hosts     = make_set(Computer, 15),
        SrcIPs    = make_set(SrcIP, 10),
        FirstSeen = min(TimeGenerated),
        LastSeen  = max(TimeGenerated)
    by Acct, bin(TimeGenerated, 1h)
| project TimeGenerated, Acct, Logons, Hosts, SrcIPs, FirstSeen, LastSeen
| order by Logons desc
```

- **MITRE technique mapping:** [T1558.002 — Steal or Forge Kerberos Tickets: Silver Ticket](https://attack.mitre.org/techniques/T1558/002/)
- **Expected match count under lab conditions:** 1 row — a silver ticket forged with the captured
  service-account NTLM hash yields a Kerberos 4624 on the service host while the DC logs no
  corresponding 4769 for that principal.
- **False positive scenarios:** ingestion gaps or DC log delay (4769 not yet collected when 4624
  arrives), multi-DC environments where the issuing DC is not onboarded, and clock skew. These
  produce transient orphan-logon noise.
- **Production tuning guidance:** ensure **all** DCs forward 4768/4769 so the `issuedTgs` set is
  complete (incomplete KDC coverage is the dominant FP source); add a small grace offset by
  binning generously; rotate service-account passwords / migrate SPNs to gMSA so forged silver
  tickets break quickly; corroborate with the absence of a matching 4769 within a `join` window
  before alerting.

---

## 9. Unconstrained Delegation Abuse

**Query name: `Unconstrained Delegation — Coerced DC Auth to a Delegation Host`**

**Log source:** SecurityEvent (4624 logon + 4768/4769 Kerberos) — a host trusted for
unconstrained delegation receives a forwardable TGT from a coerced **Domain Controller machine
account**, which the attacker then captures from LSASS.

```kql
let lookback = 6h;
// Hosts flagged as trusted for unconstrained delegation (maintain via watchlist or directory export)
let unconstrainedHosts = dynamic(["WEB01", "APP01"]);   // replace with _GetWatchlist in prod
SecurityEvent
| where TimeGenerated > ago(lookback)
| where EventID == 4624
| where LogonType in (3)
| where AuthenticationPackageName == "Kerberos"
| where toupper(Computer) has_any (unconstrainedHosts)
| extend Account = tolower(TargetUserName), SrcIP = tostring(IpAddress)
| where Account endswith "$"                       // machine account authenticating
| where Account has_any ("dc01$", "dc02$") or SrcIP != ""   // DC machine acct = coercion signal
| summarize
        Logons    = count(),
        Accounts  = make_set(Account, 15),
        SrcIPs    = make_set(SrcIP, 10),
        FirstSeen = min(TimeGenerated),
        LastSeen  = max(TimeGenerated)
    by Computer, bin(TimeGenerated, 10m)
| where Accounts has_any (dynamic(["dc01$", "dc02$"]))
| project TimeGenerated, Computer, Accounts, SrcIPs, Logons, FirstSeen, LastSeen
| order by LastSeen desc
```

```kql
// Corroboration: Print Spooler / coercion network call from the delegation host to a DC (Sysmon EID 3)
Event
| where TimeGenerated > ago(6h)
| where Source == "Microsoft-Windows-Sysmon"
| where EventID == 3
| extend ed = parse_xml(EventData)
| extend DestPort = toint(tostring(ed.DataItem.EventData.Data[14]["#text"])),
         DestIp   = tostring(ed.DataItem.EventData.Data[12]["#text"])
| where DestPort in (139, 445)                    // SMB used by PrinterBug / PetitPotam coercion
| summarize Connections = count() by Computer, DestIp, DestPort, bin(TimeGenerated, 5m)
| where Connections >= 1
| order by TimeGenerated desc
```

- **MITRE technique mapping:** [T1550.003 — Use Alternate Authentication Material: Pass the Ticket](https://attack.mitre.org/techniques/T1550/003/) (delegation abuse), related coercion vector [T1187 — Forced Authentication](https://attack.mitre.org/techniques/T1187/)
- **Expected match count under lab conditions:** 1 row — coercing `DC01$` (via PrinterBug /
  PetitPotam) to authenticate to the unconstrained-delegation host produces a `DC01$` Kerberos
  4624 on that host, plus the Sysmon SMB corroboration.
- **False positive scenarios:** legitimate inter-server Kerberos to delegation-trusted
  application/web/SQL servers, clustering and DFS replication traffic, and backup agents that
  authenticate as machine accounts. DC machine-account auth to a non-DC is the abnormal element.
- **Production tuning guidance:** drive `unconstrainedHosts` from a live directory export of
  `userAccountControl` `TRUSTED_FOR_DELEGATION` flag into a Sentinel watchlist rather than a
  hardcoded list; the highest-fidelity signal is a **DC machine account** authenticating to a
  member server — alert specifically on that; eliminate unconstrained delegation (migrate to
  constrained/RBCD, add sensitive accounts to Protected Users) so any remaining hit is suspect.

---

## 10. Cross-Forest Trust Abuse

**Query name: `Cross-Forest Trust Abuse — Foreign-Forest TGT With Elevated SID History`**

**Log source:** SecurityEvent (4768/4769 Kerberos + 4624 logon) — abuse of an inter-forest trust
(SID-history injection / inter-realm TGS) shows up as authentication referrals and logons
sourced from a foreign forest/realm targeting privileged resources.

```kql
let lookback = 24h;
let localDomain = "CORP";          // this forest's NetBIOS / realm short name
let trustedForeign = dynamic(["DEV", "DEV.LAB", "CORP.LAB"]);
SecurityEvent
| where TimeGenerated > ago(lookback)
| where EventID in (4768, 4769, 4624)
| extend Acct = tolower(TargetUserName),
         Realm = toupper(coalesce(tostring(TargetDomainName), ""))
| where isnotempty(Realm)
| where Realm != toupper(localDomain)                  // principal from a foreign realm
| where Realm has_any (trustedForeign)
| extend EncType = tostring(TicketEncryptionType), SrcIP = tostring(IpAddress)
| summarize
        Events       = count(),
        EventIds     = make_set(EventID, 5),
        Services     = make_set(ServiceName, 25),
        EncTypes     = make_set(EncType, 5),
        TargetHosts  = make_set(Computer, 15),
        SourceIPs    = make_set(SrcIP, 10),
        FirstSeen    = min(TimeGenerated),
        LastSeen     = max(TimeGenerated)
    by Acct, Realm, bin(TimeGenerated, 1h)
| where Services has_any ("krbtgt", "cifs", "ldap", "host") or EncTypes has "0x17"
| project TimeGenerated, Acct, Realm, EventIds, Services, EncTypes, TargetHosts, SourceIPs, Events, FirstSeen, LastSeen
| order by Events desc
```

- **MITRE technique mapping:** [T1134.005 — Access Token Manipulation: SID-History Injection](https://attack.mitre.org/techniques/T1134/005/) (inter-forest), related [T1558.001 — Golden Ticket](https://attack.mitre.org/techniques/T1558/001/) used to forge the inter-realm TGT
- **Expected match count under lab conditions:** 1–2 rows — a forged inter-realm TGT (or
  SID-history-laden principal) from the trusted `DEV` forest accessing `CORP` resources surfaces
  as foreign-realm Kerberos activity against privileged services.
- **False positive scenarios:** legitimate cross-forest collaboration (shared file servers,
  cross-forest Exchange/SharePoint, federated app access), migration projects that intentionally
  use SID history, and B2B scenarios. Foreign-realm auth is normal where trusts exist by design.
- **Production tuning guidance:** baseline which foreign principals legitimately access which
  local resources and watchlist them; enable **SID Filtering / Selective Authentication** on the
  trust and alert on any access that should have been filtered; ingest **Defender for Identity**
  for native inter-forest forged-PAC and SID-history detections; focus alerting on foreign-realm
  access to **tier-0** services (`krbtgt`, DC `LDAP`/`HOST`, `CIFS` on DCs) rather than ordinary
  resource shares.

---

Last updated: 2026-05-17

### MITRE ATT&CK reference links

- [T1087.002 — Account Discovery: Domain Account](https://attack.mitre.org/techniques/T1087/002/)
- [T1558.003 — Kerberoasting](https://attack.mitre.org/techniques/T1558/003/)
- [T1558.004 — AS-REP Roasting](https://attack.mitre.org/techniques/T1558/004/)
- [T1557.001 — AiTM: LLMNR/NBT-NS Poisoning and SMB Relay](https://attack.mitre.org/techniques/T1557/001/)
- [T1550.002 — Use Alternate Authentication Material: Pass the Hash](https://attack.mitre.org/techniques/T1550/002/)
- [T1003.006 — OS Credential Dumping: DCSync](https://attack.mitre.org/techniques/T1003/006/)
- [T1558.001 — Golden Ticket](https://attack.mitre.org/techniques/T1558/001/)
- [T1558.002 — Silver Ticket](https://attack.mitre.org/techniques/T1558/002/)
- [T1550.003 — Use Alternate Authentication Material: Pass the Ticket](https://attack.mitre.org/techniques/T1550/003/)
- [T1187 — Forced Authentication](https://attack.mitre.org/techniques/T1187/)
- [T1134.005 — Access Token Manipulation: SID-History Injection](https://attack.mitre.org/techniques/T1134/005/)
- [MITRE ATT&CK Enterprise Matrix](https://attack.mitre.org/matrices/enterprise/)
