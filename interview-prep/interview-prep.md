# Active Directory Attack & Detection Lab — Interview Prep

This document prepares me to present my **Active Directory (AD) attack and detection lab** as portfolio work. It contains an elevator pitch, warm-up questions, deep technical Q&A, an honest retrospective, follow-on project ideas, and a STAR-format behavioral answer. The goal is to be able to discuss the project at any depth — from a 60-second summary to protocol-level Kerberos internals — confidently and correctly.

Project artifacts referenced throughout:
- Overview: [../README.md](../README.md)
- Attack walkthroughs: [../attacks/](../attacks/)
- Sentinel KQL detections: [../detection/kql-queries.md](../detection/kql-queries.md)
- Hardening guide: [../hardening/hardening.md](../hardening/hardening.md)
- Full pentest writeup: [../writeup/writeup.md](../writeup/writeup.md)

---

## 60-Second Elevator Pitch

> "I built a from-scratch, GOAD-equivalent Active Directory lab to teach myself the full attack-and-defense lifecycle of enterprise AD. It's two forests — `sevenkingdoms.local` and a child domain `north.sevenkingdoms.local` joined by a parent-child trust — running across five VMs: two domain controllers, two member servers, and a Windows 10 workstation, all on a VirtualBox host-only network. The entire environment is reproducible with Vagrant and Ansible, so I can tear it down and rebuild it in one command. I seeded it with 25-plus themed users and ten realistic misconfigurations — Kerberoasting, AS-REP roasting, unconstrained delegation, dangerous ACLs, weak password policy, and more. Then I executed ten end-to-end attacks, from BloodHound enumeration through DCSync, Golden Tickets, and a full child-to-parent forest compromise. The part I'm proudest of is the detection layer: I deployed Sysmon, wrote Sigma rules, and authored ten Microsoft Sentinel KQL queries plus Splunk and Elastic equivalents that actually catch those attacks, with false-positive tuning. Finally, I wrote a hardening guide built on the tiered-administration model — LAPS, Protected Users, Authentication Policy Silos, gMSAs, AES-only Kerberos. So it demonstrates that I can think like an attacker, build like an engineer, and defend like a blue-teamer, all in one self-contained project."

---

## Surface-Level Q&A (Warm-Ups)

**Q1: What is this project, in one sentence?**

A: It's a self-built, reproducible Active Directory lab — equivalent to the open-source "Game of Active Directory" (GOAD) project — that I use to practice the complete offensive-and-defensive lifecycle: standing up a realistically misconfigured multi-forest AD environment, attacking it with industry-standard tooling, and then detecting and hardening against those same attacks. It's three disciplines (infrastructure, red team, blue team) in one portfolio piece.

**Q2: Why the Game of Thrones theme, and why a lab instead of just reading?**

A: The theme is borrowed from the GOAD project and is mostly practical: memorable, distinct names (kingslanding, winterfell, braavos; users like jon.snow, tywin.lannister) make it far easier to reason about a complex topology than generic `host1`/`user2` names, and it keeps the work engaging. As for the lab itself — AD attacks are destructive and noisy; you cannot ethically or safely practice DCSync or Golden Tickets on a production network or someone else's system. A disposable, isolated lab is the only responsible way to build real muscle memory. Reading teaches you *what* Kerberoasting is; running it end-to-end, seeing the 4769 event fire, and writing the detection teaches you *how* it actually behaves on the wire and in the logs.

**Q3: What is Active Directory?**

A: Active Directory is Microsoft's directory service and the identity backbone of the vast majority of enterprise networks. It centrally stores objects — users, computers, groups, and policies — in a hierarchical database and provides authentication and authorization for the whole domain. When you log into a corporate Windows machine, AD is what validates your credentials (via Kerberos or NTLM), tells you which resources you can access, and pushes down configuration through Group Policy. Because it controls *who can do what everywhere*, it's also the single highest-value target for attackers: compromise AD and you typically own the entire organization.

**Q4: What is a domain controller?**

A: A domain controller (DC) is a server that runs the Active Directory Domain Services role — it hosts the AD database (`NTDS.dit`), authenticates users and computers, and enforces security policy for its domain. In my lab, `kingslanding` is the forest-root DC for `sevenkingdoms.local` and `winterfell` is the DC for the child domain `north.sevenkingdoms.local`. DCs are the crown jewels: every user's password hash lives in `NTDS.dit`, so an attacker who gains DC-level access (or replication rights, as in DCSync) can extract every credential in the domain, including the `krbtgt` account that underpins Kerberos.

**Q5: What tools did you use?**

A: For infrastructure: VirtualBox, Vagrant, and Ansible on a Windows 11 host with WSL2. For offense: Impacket v0.12.0 (secretsdump, GetUserSPNs, GetNPUsers, ntlmrelayx), Rubeus v2.3.2, BloodHound CE 6.x for graph-based attack-path analysis, Mimikatz 2.2.0 for credential and ticket operations, and hashcat v6.2.6 for offline cracking. For defense: Sysmon v15.x with a tuned config, Sigma for portable detection rules, and Microsoft Sentinel (KQL) as the primary SIEM, with Splunk SPL and Elastic query equivalents so the detections aren't locked to one platform.

---

## Deep Technical Q&A

**Q6: Why two forests with a parent-child trust, rather than a single domain?**

A: A single domain would let me practice intra-domain attacks, but the most interesting and realistic privilege-escalation scenario in AD is *crossing a trust boundary*. By making `north.sevenkingdoms.local` a child of `sevenkingdoms.local`, I created a parent-child trust, which is automatically created, two-way, and transitive — and, critically, the parent and child are members of the *same forest*. The forest, not the domain, is the real security boundary in AD. This setup lets me demonstrate that compromising a child domain DC leads directly to forest-root (Enterprise Admin) compromise via SID History injection, because intra-forest trusts do not apply SID filtering by default. That's a lesson a single domain simply can't teach, and it mirrors how real enterprises with regional or business-unit child domains are actually structured.

**Q7: Why a parent-child trust specifically, and not an external or forest trust?**

A: The choice is deliberate because the *type* of trust changes which protections apply. A parent-child trust is intra-forest, so SID filtering (which strips foreign SIDs from an authentication token) is **not** enforced by default — that's exactly what makes the child-to-parent escalation possible and what I wanted to demonstrate. An external trust or an inter-forest trust, by contrast, enables SID filtering / quarantine by default precisely to block SID History abuse across the forest boundary. Building the parent-child variant teaches the most important nuance in AD trust security: people assume "trust = boundary," but the real boundary is the forest, and within it the domains are effectively one security context. A future iteration could add a separate forest with a forest trust to contrast the two behaviors directly.

**Q8: Why VirtualBox + Vagrant + Ansible, over alternatives like Hyper-V, Terraform, or the cloud?**

A: VirtualBox is free, cross-platform, and has first-class Vagrant support, which matters because the whole point was a *reproducible* lab anyone could clone. Hyper-V conflicts with VirtualBox's hypervisor on the same host and has weaker Vagrant tooling, so running both is painful. Vagrant handles VM lifecycle and the host-only networking declaratively; Ansible handles in-guest configuration — domain promotion, user creation, GPO and misconfiguration seeding — which is idempotent and far more maintainable than brittle PowerShell DSC or click-ops. Terraform is excellent for cloud/immutable infrastructure but is overkill for local mutable VMs where Vagrant already covers provisioning. I chose local over cloud deliberately: no hourly billing, full network isolation for safely detonating malware-like tooling, and no risk of an exposed misconfigured DC on the internet. The tradeoff is local resource cost, which leads into sizing.

**Q9: How did you size the VMs and the host?**

A: Five VMs on a single Windows 11 host means RAM is the binding constraint. Domain controllers and Sysmon-instrumented Windows Server are memory-hungry, so I budgeted roughly 2-4 GB per server VM and 2 GB for the Windows 10 workstation, targeting a host with at least 32 GB so I'm not thrashing swap when all five run concurrently — though most attack scenarios only need two or three VMs up at once, so I rarely run the full topology. CPU is less of a bottleneck than RAM for AD workloads, so 1-2 vCPUs per VM is fine. Disk uses linked clones / dynamically allocated VDIs to avoid pre-committing hundreds of gigabytes. The Ansible provisioning is the slow part of a cold build, so I rely on Vagrant snapshots to checkpoint a clean, fully provisioned state and roll back instantly after a destructive attack rather than rebuilding from scratch each time.

**Q10: Walk me through Kerberoasting at the protocol level — why is it possible and why are the tickets crackable?**

A: Kerberoasting abuses a fundamental design feature of Kerberos. Any authenticated domain user can request a service ticket (TGS) for any service that has a Service Principal Name (SPN) registered — that's the TGS-REQ/TGS-REP exchange. The KDC returns a TGS whose service portion is encrypted with the *service account's password-derived key*. The attacker doesn't need any access to the service itself; they just request the ticket (with Impacket's GetUserSPNs or Rubeus) and crack it offline. The vulnerability is that if the account's encryption type allows RC4 (etype 0x17 / RC4-HMAC), the key is the straight NT hash of the password — unsalted MD4 — which hashcat (mode 13100) can attack at enormous speeds. AES (etypes 0x11/0x12) uses PBKDF2 with 4096 iterations and a salt, making it orders of magnitude slower to crack, and Kerberoasting *only* yields a meaningful win when the SPN is on a *user* account (not a managed/computer account) with a weak, human-set password. My lab intentionally has service accounts with RC4 enabled and weak passwords so the attack succeeds; the fix — AES-only and gMSAs with 120-character random passwords — makes the cracked ticket computationally worthless even if the attacker obtains it.

**Q11: How does AS-REP roasting differ, and what's the pre-authentication mechanic?**

A: AS-REP roasting targets the *authentication-service* exchange (AS-REQ/AS-REP) rather than the ticket-granting one, and it requires no prior credentials at all — just a list of usernames. Normally Kerberos pre-authentication forces the client to prove it knows the password *before* the KDC sends anything back: the client encrypts a timestamp with its password-derived key (the PA-ENC-TIMESTAMP), and the KDC only responds if it decrypts correctly. This is what prevents an attacker from harvesting crackable material for arbitrary accounts. But if an account has "Do not require Kerberos preauthentication" set (the `DONT_REQ_PREAUTH` UAC flag), the KDC will return an AS-REP to *anyone* who asks, and part of that response is encrypted with the account's password key. Impacket's GetNPUsers harvests those AS-REPs, and hashcat mode 18200 cracks them offline. So the attack surface is much smaller than Kerberoasting (only pre-auth-disabled accounts), but it requires zero authentication, making it a powerful early-access technique. My lab has at least one user with pre-auth disabled to demonstrate it.

**Q12: Explain DCSync and the specific rights it abuses.**

A: DCSync is credential theft by impersonating a domain controller. AD uses the Directory Replication Service (DRS) Remote Protocol (specifically the `IDL_DRSGetNCChanges` call) so DCs can replicate directory data — including secrets like password hashes — to each other. DCSync simply *speaks that protocol* to a real DC and asks it to replicate the secrets for a target account (or all accounts), without ever logging onto the DC or touching `NTDS.dit` directly. What gates this is a small set of extended rights on the domain object: `DS-Replication-Get-Changes`, `DS-Replication-Get-Changes-All`, and (for some objects) `Replicating Directory Changes In Filtered Set`. Any principal granted those rights — normally only DCs and high-tier admins, but sometimes mistakenly delegated via a dangerous ACL — can run `mimikatz "lsadump::dcsync /user:krbtgt"` or Impacket's `secretsdump`. Pulling the `krbtgt` hash this way is the precursor to a Golden Ticket. The reason it's so dangerous and so beloved by attackers is that it looks like legitimate replication traffic and produces no logon to the DC, which is exactly why detection has to key on the replication activity itself (event 4662 with the replication GUID — see the detection section).

**Q13: Golden Ticket vs. Silver Ticket — what's the difference, and which is worse?**

A: Both are forged Kerberos tickets, but they forge different things. A **Golden Ticket** is a forged TGT (ticket-granting ticket), signed with the `krbtgt` account's hash. Because the KDC trusts any TGT encrypted with the `krbtgt` key, a Golden Ticket lets the attacker impersonate *anyone* — including Domain Admin — to *any* service in the domain, and it can be created with an arbitrary, long lifetime. It's effectively a domain-wide skeleton key that survives password resets of every account *except* `krbtgt`. A **Silver Ticket** is a forged TGS for one specific service, signed with *that service account's* hash (e.g., a computer account's machine key for CIFS or HOST). It's narrower — only that one service on that one host — but stealthier, because it never contacts the KDC at all (no TGS-REQ, so no 4769 event on the DC). Golden is "worse" in scope and persistence; Silver is "worse" for evasion. Remediation for Golden is the dreaded *double* `krbtgt` password reset (twice, to flush the password history that Kerberos keeps for two generations); Silver requires resetting the affected service/computer account.

**Q14: Why is unconstrained delegation so dangerous, and how does coercion amplify it?**

A: With unconstrained delegation, when a user authenticates to a server configured for it, the user's *full TGT* is cached in the server's LSASS memory so the server can impersonate that user to any back-end service. The danger is that an attacker who compromises that one server can extract every TGT that lands on it — and if they can lure a privileged account (especially a Domain Controller's machine account) to authenticate to that server, they capture a TGT they can replay for domain compromise. That "if they can lure" used to be the limiting factor, until coercion techniques removed it: tools abusing the Print Spooler (PrinterBug / SpoolSample) or EFSRPC (PetitPotam) can *force* a target machine — including a DC — to authenticate to an attacker-controlled host on demand. So the chain becomes: compromise a host with unconstrained delegation, run a coercion to force the DC's machine account to authenticate to it, capture the DC's TGT, and then DCSync. That's exactly why my lab leaves the Print Spooler running on DCs (a documented misconfiguration) and why the hardening guide disables it, marks DCs as "sensitive — cannot be delegated," and uses the Protected Users group.

**Q15: How does the child-to-parent forest escalation work, and why doesn't SID filtering stop it?**

A: Once I have Domain Admin (or the `krbtgt` hash) in the child domain `north.sevenkingdoms.local`, I escalate to forest-root Enterprise Admin using SID History. I forge a Golden Ticket for a child-domain user but inject an *extra* SID into the ticket's SID History field — specifically the well-known RID 519 SID of the **Enterprise Admins** group in the parent domain (`<root-domain-SID>-519`). When that ticket is presented to a resource in the parent domain, the parent's KDC reads the SID History and grants the token Enterprise Admin authorization. The reason this isn't blocked is the crucial nuance: **SID filtering is not applied to intra-forest trusts**. SID filtering exists to strip foreign SIDs from tokens crossing a trust, but it's only enabled by default on *external* and *inter-forest* trusts, because within a single forest all domains are considered one security and trust boundary — the parent-child trust is intra-forest. So the parent domain *trusts* the SID History coming from its own child, by design. This is the single most important takeaway of the whole lab: a "child domain" is not a security boundary; compromising it compromises the forest. The only real mitigation is treating the entire forest as one Tier 0 blast radius. The full chain is documented in [../writeup/writeup.md](../writeup/writeup.md).

**Q16: Why Sysmon, and what does it give you that native Windows logging doesn't?**

A: Native Windows Security auditing is essential but coarse and noisy by default — and many of the events you need (detailed process creation with command lines, network connections, image loads, hashes) are either off, under-configured, or simply not captured. Sysmon (System Monitor) is a free Sysinternals driver and service that writes high-fidelity telemetry to a dedicated event log: process creation *with full command line and parent process* (Event ID 1), network connections (ID 3), image/DLL loads (ID 7), process access (ID 10, great for catching LSASS reads by Mimikatz), and more. Crucially, Sysmon is *configuration-driven* — I run a tuned config (based on community baselines like SwiftOnSecurity/Olaf Hartong) that filters out benign noise at the source so the SIEM only ingests signal. For an AD attack lab, Event ID 10 (process access to lsass.exe) and Event ID 1 (command-line capture of `mimikatz`, `rubeus`, `GetUserSPNs`) are detection gold that native logging alone won't reliably give you.

**Q17: Walk me through your Kerberoasting detection logic on Event ID 4769.**

A: Event ID 4769 ("A Kerberos service ticket was requested") is logged on the DC for every TGS-REQ. The naive approach — alert on all 4769 — is useless because that event fires constantly during normal operation. The signal for Kerberoasting is in the fields: the **Ticket Encryption Type** of `0x17` (RC4-HMAC) is suspicious in a modern, AES-capable domain because legitimate Windows clients negotiate AES (0x12) by default — RC4 is the attacker downgrading to get a crackable ticket. So my KQL keys on `TicketEncryptionType == "0x17"`, then adds context to cut false positives: exclude tickets for the `krbtgt` SPN, exclude machine accounts (`$`-suffixed), and watch for *one source account requesting many distinct SPNs in a short window* (the bulk-roasting signature, since GetUserSPNs/Rubeus enumerate and request many at once). I also enrich with Failure Code `0x0` (success) and the Ticket Options. The combination — RC4 + bulk distinct SPNs from a single non-machine account — is a high-confidence Kerberoasting indicator. These queries live in [../detection/kql-queries.md](../detection/kql-queries.md).

**Q18: How do you detect DCSync, given it generates no logon to the DC?**

A: Exactly because there's no interactive or network logon to the DC, you can't detect DCSync with logon events — you have to detect the *replication request itself*. The key is Event ID 4662 ("An operation was performed on an object"), which fires when the directory replication extended rights are exercised. The detection looks for a 4662 where the `Properties` field contains the replication control-access-right GUIDs — specifically `1131f6aa-9c07-11d1-f79f-00c04fc2dcd2` (DS-Replication-Get-Changes) and `1131f6ad-9c07-11d1-f79f-00c04fc2dcd2` (DS-Replication-Get-Changes-All) — performed by an account that is **not** itself a domain controller. Legitimate replication is DC-to-DC (machine accounts ending in `$` that are members of the Domain Controllers / Enterprise Domain Controllers groups), so the tuning is: alert on those GUIDs when the requesting account is a *normal user or non-DC computer*. That single rule catches both Mimikatz `lsadump::dcsync` and Impacket `secretsdump`, regardless of which user they target.

**Q19: How did you approach false-positive tuning, and was it worth the effort?**

A: False positives are what make or break a detection program — an alert that fires a hundred times a day for benign reasons gets muted, and then it misses the real attack. My tuning approach was iterative and evidence-based: I'd run an attack to confirm the detection *fires* (true positive), then run the lab through a few days of normal-ish activity — logons, GPO refreshes, replication, admin tasks — and see what *else* fired (false positives), then add exclusions tied to legitimate behavior rather than blanket-suppressing. Concrete examples: excluding `krbtgt` and machine accounts from the 4769 RC4 rule; excluding bona fide DCs from the 4662 replication rule; baselining which service accounts legitimately use RC4 (and ideally fixing them rather than excepting them); and using thresholds/time-windows for "bulk" behavior instead of single-event triggers. Was it worth it? Absolutely — it's the difference between a demo and a deployable detection. The honest gap is that my lab lacks realistic background noise (see "what I'd do differently"), so my false-positive baseline is optimistic compared to a real enterprise.

**Q20: Why write detections in KQL *and* Sigma *and* Splunk/Elastic — isn't that redundant?**

A: It's intentional, and it demonstrates a real-world detection-engineering skill: portability and tool-agnostic thinking. **Sigma** is the lingua franca — a YAML-based, vendor-neutral detection format — so I author the *logic* once in Sigma and it can be converted (via sigmac/pySigma) to many backends. That's the source of truth. **KQL for Microsoft Sentinel** is my primary, fully-realized SIEM target because Sentinel is extremely common in enterprises and KQL is expressive for the join/enrichment-heavy AD detections. I then provide **Splunk SPL** and **Elastic** equivalents because in interviews and in real jobs you don't get to pick the SIEM — the org already has one. Showing the same detection across three platforms proves I understand the *underlying telemetry and logic*, not just one query language, and that I can port a detection when I change employers or tools. It also surfaces the subtle per-platform differences (field naming, how each handles the 4662 Properties GUID matching) that you only learn by actually doing it.

**Q21: Hardening tradeoff — Protected Users group breaks things. Walk me through it.**

A: The Protected Users group is one of the strongest, cheapest hardening controls for Tier 0 accounts: members can't use NTLM, can't use RC4 or DES Kerberos, can't be delegated (no constrained or unconstrained delegation), and their TGTs aren't cached and have a forced 4-hour lifetime — which directly defeats credential theft, Pass-the-Hash, and Kerberoasting against those accounts. The tradeoff is that those very restrictions *break legitimate functionality that relies on the disabled mechanisms*. If an admin account needs delegation to function, putting it in Protected Users breaks it. Any service or app still using NTLM or RC4 for that account fails. The short 4-hour TGT can disrupt long-running sessions. So the discipline is: Protected Users is for *human privileged accounts* (Domain/Enterprise Admins), never for service accounts or computer accounts, and you roll it out in a pilot ring while monitoring 4625/4771 failures to catch what breaks. It's documented as a Tier 0 control in [../hardening/hardening.md](../hardening/hardening.md).

**Q22: AES-only Kerberos and gMSA — what do they fix and what do they cost?**

A: Forcing **AES-only** Kerberos (disabling RC4/DES on accounts and via the "Network security: Configure encryption types allowed for Kerberos" policy) is the direct kill for both Kerberoasting crackability and RC4 downgrade attacks — AES keys are salted and PBKDF2-stretched, so even a stolen ticket is impractical to crack. The cost is legacy compatibility: old appliances, NetApp filers, certain Linux/Java Kerberos clients, or apps with hardcoded RC4 will fail to authenticate, so you must inventory and remediate them first or you cause an outage. **gMSA** (group Managed Service Accounts) attacks the *other* half of the problem — the weak human-chosen service-account password. A gMSA has a 120-character, fully random password that AD rotates automatically (default every 30 days), so even if it's Kerberoastable in principle, it's uncrackable, and there's no human in the loop forgetting to rotate it. The tradeoff versus manual rotation is that gMSAs require the app/service to support them (most modern Microsoft services do; some third-party apps don't), Server 2012+ DCs, and the KDS root key configured. Manual rotation is the fallback for apps that can't use gMSA — but manual rotation is exactly what humans skip, which is why those accounts get Kerberoasted in the first place. So gMSA-where-possible, AES-only everywhere, manual-rotation-with-a-strong-password as the last resort.

**Q23: Authentication Policies and Silos — what's the blast-radius benefit and the operational risk?**

A: Authentication Policies and Authentication Policy Silos are a Server 2012 R2+ feature that lets you *constrain where privileged accounts can authenticate from*. A Silo is a container for accounts, computers, and services; a Policy attached to it can enforce, for example, "Domain Admin accounts can only get a TGT when logging on from a designated Privileged Access Workstation (PAW)" and restrict TGT lifetime. The blast-radius benefit is huge: even if an attacker steals a Domain Admin's hash or credentials, those credentials are *useless from a normal workstation or member server* because the KDC refuses to issue a TGT outside the silo — it directly contains lateral movement and credential-theft impact, complementing the tiering model. The operational risk is that it's a hard, fail-closed control: misconfigure the allowed computers or forget to add a needed jump host, and you lock your own admins out of the very accounts they need for recovery — a self-inflicted denial of service on Tier 0. So you deploy it carefully, in audit mode first, with break-glass accounts excluded and a tested recovery path, after the PAW infrastructure actually exists. It's the capstone control in the tiered model, not the starting point.

---

## What I Would Do Differently

Being honest about a portfolio project's limits is itself a signal of maturity, so here's where I'd push it further:

- **CI/CD for provisioning.** Right now a rebuild is a manual `vagrant up` plus Ansible run. I'd put the provisioning under a pipeline (GitHub Actions or GitLab CI) with `ansible-lint`, idempotence checks, and a smoke test that verifies the domain came up and the misconfigurations seeded correctly — treating the lab itself as tested infrastructure-as-code.
- **ADCS / certificate attacks (ESC1–ESC8).** The biggest gap. Active Directory Certificate Services attacks are arguably the most impactful AD privilege-escalation class of the last few years and my lab doesn't include AD CS at all. I'd add a CA and the ESC misconfigurations and detect them with Certipy on the offense side.
- **Cloud / Entra ID hybrid.** Real enterprises are hybrid now. I'd connect the on-prem AD to Entra ID via Entra Connect and explore hybrid attack paths (PRT theft, seamless SSO / `AZUREADSSOACC$` Silver Tickets, sync-account abuse) — that's where the industry actually is.
- **Automated detection testing.** My detections are validated by hand. I'd integrate **Atomic Red Team** (and/or Caldera) to programmatically execute ATT&CK techniques on a schedule and assert that each corresponding detection fires — turning detection validation into a repeatable, regression-tested purple-team loop.
- **Realistic background noise.** My false-positive baseline is optimistic because the lab is quiet. I'd add simulated user activity, scheduled tasks, software deployments, and routine admin work so detections are tuned against realistic noise, not a sterile environment.

---

## Follow-Up Project Ideas

1. **AD CS ESC1–ESC8 attack & detection lab.** A dedicated environment standing up Active Directory Certificate Services with each of the well-known misconfigurations (vulnerable templates, NTLM relay to web enrollment, etc.), attacked with Certipy and detected via certificate-enrollment auditing and the relevant event IDs. This closes the single biggest gap in the current lab.

2. **Entra ID / hybrid-identity attack lab.** Extend the on-prem forest into a hybrid environment with Entra Connect and explore the cloud attack surface: Primary Refresh Token (PRT) theft, Seamless SSO Silver Tickets against `AZUREADSSOACC$`, sync-service-account abuse, conditional-access bypasses, and detection via Entra ID sign-in / audit logs in Sentinel.

3. **Automated purple-team detection pipeline.** A standalone project wrapping Atomic Red Team + a SIEM where every ATT&CK technique execution is automatically correlated against its expected detection, producing a coverage matrix and alerting on detection regressions — essentially CI for blue-team detections, reusable across any environment.

---

## STAR Behavioral Answer

**Prompt:** "Tell me about a project you're proud of / a time you taught yourself something complex."

- **Situation:** I wanted to move from theoretical knowledge of Active Directory security into demonstrable, hands-on capability across both offense and defense, but practicing AD attacks on any real or shared system is unsafe and unethical — these techniques are destructive and can't be ethically rehearsed against production.

- **Task:** I set out to build, from scratch, a fully isolated, reproducible enterprise-grade AD lab — equivalent to the well-known GOAD project — and use it to execute, detect, and harden against the full range of modern AD attacks, documenting everything to a professional standard.

- **Action:** I designed a two-forest topology (a root domain and a child domain joined by a parent-child trust) across five VMs on an isolated VirtualBox host-only network, and made the entire build reproducible with Vagrant and Ansible so it could be torn down and rebuilt on demand. I seeded 25-plus users and ten realistic misconfigurations, then executed ten end-to-end attacks — BloodHound enumeration, Kerberoasting, AS-REP roasting, NTLM relay, Pass-the-Hash, DCSync, Golden and Silver Tickets, unconstrained-delegation abuse, and a full child-to-parent forest compromise via SID History. For the defensive half I deployed Sysmon, authored Sigma rules and ten Microsoft Sentinel KQL detections (plus Splunk and Elastic equivalents), and tuned out false positives by baselining normal activity. I then wrote a tiered-administration hardening guide (LAPS, Protected Users, Authentication Policy Silos, gMSA, AES-only Kerberos) and a full pentest writeup with CVSS-scored findings.

- **Result:** I produced a complete, reproducible portfolio piece that exercises three disciplines — infrastructure engineering, red-team tradecraft, and blue-team detection engineering — and, more importantly, I internalized *why* each attack works at the protocol level and *how* to detect and prevent it. I can now confidently discuss AD security from a 60-second pitch down to Kerberos encryption-type internals, and I have a documented, defensible artifact ([../README.md](../README.md), [../attacks/](../attacks/), [../detection/kql-queries.md](../detection/kql-queries.md), [../hardening/hardening.md](../hardening/hardening.md), [../writeup/writeup.md](../writeup/writeup.md)) to back it up.

---

Last updated: 2026-05-17

### MITRE ATT&CK References
- T1558.003 — Steal or Forge Kerberos Tickets: Kerberoasting — https://attack.mitre.org/techniques/T1558/003/
- T1558.004 — Steal or Forge Kerberos Tickets: AS-REP Roasting — https://attack.mitre.org/techniques/T1558/004/
- T1558.001 — Steal or Forge Kerberos Tickets: Golden Ticket — https://attack.mitre.org/techniques/T1558/001/
- T1558.002 — Steal or Forge Kerberos Tickets: Silver Ticket — https://attack.mitre.org/techniques/T1558/002/
- T1003.006 — OS Credential Dumping: DCSync — https://attack.mitre.org/techniques/T1003/006/
- T1550.002 — Use Alternate Authentication Material: Pass the Hash — https://attack.mitre.org/techniques/T1550/002/
- T1187 — Forced Authentication (coercion: PrinterBug / PetitPotam) — https://attack.mitre.org/techniques/T1187/
- T1557.001 — Adversary-in-the-Middle: LLMNR/NBT-NS Poisoning and SMB Relay — https://attack.mitre.org/techniques/T1557/001/
- T1134.005 — Access Token Manipulation: SID-History Injection — https://attack.mitre.org/techniques/T1134/005/
- T1482 — Domain Trust Discovery — https://attack.mitre.org/techniques/T1482/
- T1087.002 — Account Discovery: Domain Account (BloodHound) — https://attack.mitre.org/techniques/T1087/002/
- T1484.001 — Domain Policy Modification: Group Policy Modification — https://attack.mitre.org/techniques/T1484/001/
