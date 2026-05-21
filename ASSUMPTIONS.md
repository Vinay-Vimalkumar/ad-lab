# Assumptions & Decisions Log

This file records decisions made where the project specification was ambiguous, silent, or internally in tension. Each entry states the ambiguity, the decision taken, and the rationale, so a reviewer can see *why* the documentation reads the way it does.

> Scope note: this log covers the **documentation track** (markdown, attack walkthroughs, KQL, analysis). Infrastructure files (`Vagrantfile`, Ansible, PowerShell, Sysmon XML, Sigma, Splunk/Elastic queries) are owned by a separate track and are only *referenced* here, not authored.

---

## Environment & paths

| # | Ambiguity | Decision | Rationale |
|---|-----------|----------|-----------|
| A1 | The brief names the repo root both as `C:\Users\vinay\ad-lab\` (authorization scope) and the live working directory resolves to `c:\Users\vinay\Downloads\ad-lab`. | All files written under the **actual working directory** `c:\Users\vinay\Downloads\ad-lab`. | That is the initialized git repo. Relative cross-links inside the docs are path-agnostic, so they remain correct regardless of where the repo is cloned. |
| A2 | "Today's date" context says 2026-05-20, but the brief mandates every file end with `Last updated: 2026-05-17`. | Used **2026-05-17** in every footer as instructed. | Explicit spec requirement overrides the ambient date; keeps all files internally consistent. |

## Lab topology & roles

| # | Ambiguity | Decision | Rationale |
|---|-----------|----------|-----------|
| A3 | The 4 Kerberoastable SPNs reference hosts `sql01`, `web01`, `fileserver`, `app01` that are **not** in the 5-VM inventory. | Treated these as **logical SPN hostnames** registered to service accounts, not additional VMs. `sql01/web01/fileserver` resolve conceptually to **castelblack** (the sevenkingdoms member server); `app01` to a north service. | Keeps the 5-VM footprint fixed (matches resource budget) while preserving realistic, crackable SPNs. GOAD does the same — SPNs need not map 1:1 to running hosts to be roastable. |
| A4 | No attacker machine is defined in the VM inventory. | Assumed the **operator runs Linux tooling (Impacket, Responder, netexec) from the Windows 11 host via WSL2**, reachable on the host-only network as `192.168.56.1` (the VirtualBox host-only gateway). Windows-only tooling (Rubeus, Mimikatz, SharpHound) is run from **braavos** or a compromised member when a domain context is required. | Avoids adding a 6th VM (RAM budget); WSL2 is already a prerequisite for Ansible. `192.168.56.1` is the default VirtualBox host-only adapter address for the `192.168.56.0/24` network. |
| A5 | Parent-child trust direction/transitivity not fully specified. | Documented as a **two-way, transitive, intra-forest parent-child trust** with **SID filtering not enforced** (default for same-forest trusts). | This is the default and is *required* for the cross-forest/child→parent SID-History escalation in attack 10 to be demonstrable. |
| A6 | "Cross-forest" trust abuse (attack 10) vs. the topology being a single forest with two domains. | Documented it as **intra-forest child→parent (north → sevenkingdoms) domain escalation** to Enterprise Admin, while keeping the brief's "cross-forest" filename/label. | Strictly, `north.sevenkingdoms.local` is a child *domain* in the same *forest*, not a separate forest. The privilege-escalation technique (SID History to the root domain's Enterprise Admins / inter-realm trust key) is the realistic, working primitive; the doc notes this distinction explicitly. |

## Attacks & tooling

| # | Ambiguity | Decision | Rationale |
|---|-----------|----------|-----------|
| A7 | Exact attack-tool invocation host not always implied. | Every step explicitly states the host/VM it runs from. | Brief requirement; removes ambiguity for a reader reproducing the lab. |
| A8 | Sample outputs (hashes, tickets) needed but must not leak anything real. | Provided **realistic but synthetic** literal outputs (placeholder hashes, fabricated SIDs/RIDs) and used `{{LAB_PASSWORD}}` with an inline note that it equals `Password123!`. | Satisfies the "literal sample output" requirement without committing crackable real material; lab password is intentionally insecure and public anyway. |
| A9 | Attack 9 (unconstrained delegation) has no MITRE ID in the brief. | Mapped to primary **T1550.003 (Pass the Ticket)** + **T1187 (Forced Authentication)** for the printerbug/coercion step. | Most accurate ATT&CK mapping for capturing and replaying a coerced machine TGT. |

## Detection (KQL)

| # | Ambiguity | Decision | Rationale |
|---|-----------|----------|-----------|
| A10 | Sysmon ingestion shape in Sentinel not specified. | Assumed Sysmon is ingested via **AMA into the `Event` table** and parsed with `parse_xml(EventData)`; Defender-style queries use `DeviceProcessEvents`/`DeviceNetworkEvents`/`IdentityLogonEvents` where more appropriate. | Most common modern Sentinel onboarding path; keeps queries runnable. The doc states the assumed log source per query. |
| A11 | Forged-ticket detections (golden/silver) have no single decisive Event ID. | Used **anomaly/absence logic** (e.g. TGS-REP without a corresponding TGT-REQ, anomalous ticket lifetimes) expressed as valid `let`-bound KQL. | Forged tickets are detected by inconsistency, not a single signature; this is the honest, production-realistic approach. |

## Cross-track references

| # | Ambiguity | Decision | Rationale |
|---|-----------|----------|-----------|
| A12 | Many links point to files owned by the infrastructure track that may not exist yet (`Vagrantfile`, hardening `.ps1` scripts, `sigma-rules/`, `sysmon-config.xml`, `splunk-queries.md`, `elastic-queries.md`). | **Linked to their canonical paths anyway**, per the agreed shared conventions, and did **not** create them. | The two tracks share one naming convention; links resolve once the counterpart track lands its files. Authoring them here would collide with the other track. |

---

Last updated: 2026-05-17
MITRE ATT&CK: <https://attack.mitre.org/>
