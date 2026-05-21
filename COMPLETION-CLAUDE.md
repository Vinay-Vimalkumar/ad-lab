# Completion Report — Documentation Track (Claude)

**Date:** 2026-05-17 · **Branch:** `main` · **Scope:** all markdown documentation, attack walkthroughs, KQL detections, and analysis. Infrastructure files (Vagrantfile, Ansible, PowerShell, Sysmon XML, Sigma, Splunk/Elastic queries) were authored by the parallel track (Codex) and are only *referenced* here.

No `git add` / `commit` / `push` was run, per instructions — only `git status` for verification.

## Files written

### Root
| File | Lines | Description |
|------|-------|-------------|
| `README.md` | 185 | Project overview: shields.io badges, mermaid architecture diagram, TOC, VM inventory, attack catalog table, detection catalog, MITRE ATT&CK mapping, repo tree, links to every deliverable |
| `ASSUMPTIONS.md` | 49 | Decision log for ambiguous/under-specified points (attacker host model, SPN→host mapping, intra- vs cross-forest framing, KQL log-source assumptions, date footer) |
| `.gitignore` | 83 | Vagrant/VirtualBox/Ansible artifacts, captured loot (hashes, tickets, ntds.dit), Python/WSL cruft, secrets, OS/editor files |

### docs/ (host setup & operations)
| File | Lines | Description |
|------|-------|-------------|
| `docs/00-environment-setup.md` | 370 | Win 11 Pro N preflight: disable Hyper-V (DISM + `Disable-WindowsOptionalFeature` + `bcdedit` + VBS/Credential Guard), VirtualBox 7.x SHA256-verified install, Vagrant + vbguest, WSL2 Ubuntu 22.04, Ansible via apt/pipx + galaxy collections; verification outputs + troubleshooting (VT-x, Hyper-V re-enabling, WSL networking, VBoxNetAdpCtl) |
| `docs/01-lab-architecture.md` | 160 | VM inventory matching shared conventions, network topology + OU mermaid diagrams, IP/hostname scheme, parent-child trust model, resource footprint |
| `docs/02-quick-start.md` | 143 | 15-minute getting-started: clone → prereqs → `vagrant up` → provision → smoke test, with mermaid timeline + success checklist |
| `docs/03-troubleshooting.md` | 88 | Symptom/Cause/Fix tables across VirtualBox, Vagrant, Ansible/WinRM, domain join, attack tools (incl. KRB_AP_ERR_SKEW, wrong-DC DNS) |
| `docs/04-cleanup-and-reset.md` | 171 | Snapshot management, restore, selective/full teardown, disk reclamation, post-attack reset recipe, mermaid lifecycle |

### attacks/ (10 MITRE-mapped walkthroughs)
| File | Lines | MITRE | Description |
|------|-------|-------|-------------|
| `attacks/01-bloodhound-enumeration.md` | 154 | T1087.002 | SharpHound + bloodhound-python collection, BloodHound CE 6.x cypher paths surfacing planted ACLs |
| `attacks/02-kerberoasting.md` | 138 | T1558.003 | Impacket GetUserSPNs + Rubeus on 4 SPN accounts, hashcat -m 13100 |
| `attacks/03-asrep-roasting.md` | 132 | T1558.004 | GetNPUsers + Rubeus on jon/arya/sansa, hashcat -m 18200 |
| `attacks/04-ntlm-relay.md` | 139 | T1557.001 | Responder LLMNR/NBT-NS + ntlmrelayx SMB relay to castelblack, SAM dump |
| `attacks/05-pass-the-hash.md` | 127 | T1550.002 | netexec/psexec -hashes lateral movement to SYSTEM |
| `attacks/06-dcsync.md` | 176 | T1003.006 | Mimikatz dcsync + secretsdump for krbtgt/Administrator hashes |
| `attacks/07-golden-ticket.md` | 176 | T1558.001 | Forged TGT via krbtgt hash + domain SID (Mimikatz/ticketer), PtT to DC |
| `attacks/08-silver-ticket.md` | 168 | T1558.002 | Forged CIFS TGS from machine hash, no DC contact (Rubeus/Mimikatz) |
| `attacks/09-unconstrained-delegation.md` | 157 | T1550.003 / T1187 | Rubeus monitor + printerbug coercion to capture DC TGT → DCSync |
| `attacks/10-cross-forest-trust-abuse.md` | 178 | T1134.005 / T1558.001 | Child→parent escalation via SID History + inter-realm trust key |

Each follows the required section order: title w/ MITRE ID, intro, technique link, prerequisites, versioned tools, per-host numbered commands, literal expected output, screenshot placeholders (`attack-N-step-M.png`), cleanup, "What This Tells You About AD", detection reference, dated footer.

### detection/
| File | Lines | Description |
|------|-------|-------------|
| `detection/kql-queries.md` | 589 | 10 Microsoft Sentinel KQL queries (one per attack) with log source, MITRE mapping, expected lab match count, false-positive scenarios, production tuning. Real Event IDs (4768/4769/4662 replication GUIDs/4624/5145) + Sysmon EID 1/3/10/11/22. References Codex's `sigma-rules/` and `sysmon-config.xml` |

### hardening/, writeup/, interview-prep/, screenshots/
| File | Lines | Description |
|------|-------|-------------|
| `hardening/hardening.md` | 509 | Tier 0/1/2 model (mermaid), 16 controls (Protected Users, LAPS, SMB/LDAP signing, FAST, Auth Policies/Silos, disable SMBv1/NTLMv1/LLMNR, kill unconstrained delegation, spooler, anonymous LDAP, FGPP, gMSA, AES-only, ACL fixes) each w/ rationale/impact/MITRE mitigation/script link/validation/blast radius; effort-impact matrix + quadrant |
| `writeup/writeup.md` | 568 | Pentest report: exec summary, methodology (CIS v8/NIST 800-115/ATT&CK) + kill-chain mermaid, 10 CVSS 3.1 findings (4 Critical / 5 High / 1 Medium), detection gap analysis, 30/60/90 hardening roadmap, appendix (tool versions, command ref, glossary) |
| `interview-prep/interview-prep.md` | 170 | 60-sec pitch, 5 surface + 15 deep technical Q&A, "what I'd do differently", 3 follow-up project ideas, STAR answer |
| `screenshots/README.md` | 44 | Naming convention (`attack-N-step-M.png`), attack-number map, capture guidelines |
| `screenshots/.gitkeep` | 0 | Keeps the empty evidence directory in a fresh clone |

**Total docs-track output: ~4,674 lines across 24 files.**

## Validation performed
- ✅ Every markdown file ends with `Last updated: 2026-05-17` + MITRE reference links (22/22).
- ✅ All `.md` cross-links resolve to existing files; detection anchors verified against KQL H2 headings.
- ✅ Fixed 2 anchor mismatches: `attacks/03` (`#3-asrep-roasting` → `#3-as-rep-roasting`) and `attacks/09` (`#9-unconstrained-delegation` → `#9-unconstrained-delegation-abuse`).
- ✅ Mermaid blocks balanced; diagram types used (flowchart, graph, sequenceDiagram, stateDiagram-v2, quadrantChart) are GitHub-renderable.
- ⚠️ `mermaid-cli` / Node / npm were **not available** on the host, so diagrams were validated by inspection (syntax + balanced fences) rather than headless render. Install Node + `@mermaid-js/mermaid-cli` to run `mmdc` if a render check is desired.

## Assumptions (full detail in ASSUMPTIONS.md)
1. Used the live working directory `c:\Users\vinay\Downloads\ad-lab` (the brief also named `C:\Users\vinay\ad-lab`); relative links are path-agnostic.
2. Footers use `2026-05-17` per the brief, overriding the ambient date (2026-05-20).
3. SPN hosts (`sql01/web01/fileserver/app01`) are logical SPNs on existing VMs, not extra VMs — keeps the 5-VM footprint.
4. Attacker tooling runs from WSL2 on the host (`192.168.56.1`); Windows-only tools run from `braavos` / compromised members.
5. Parent-child trust documented as two-way transitive with SID filtering off (required for attack 10).
6. Attack 10 framed as intra-forest child→parent escalation while retaining the brief's "cross-forest" label.
7. Sample hashes/tickets are synthetic; `{{LAB_PASSWORD}}` = `Password123!` noted inline.
8. KQL assumes Sysmon ingested into the `Event` table (AMA, `parse_xml`); Defender tables used where more appropriate. Forged-ticket detections use anomaly/absence logic.
9. Links to infra-track files (Vagrantfile, hardening `.ps1`, sigma/sysmon/splunk/elastic) use canonical shared paths; not authored here.

## Out of scope (Codex's lane — untouched)
`infrastructure/Vagrantfile`, `infrastructure/provisioning/ansible/*`, `infrastructure/provisioning/scripts/*.ps1`, `detection/sysmon-config.xml`, `detection/sigma-rules/*.yaml`, `detection/splunk-queries.md`, `detection/elastic-queries.md`, `CODEX-ASSUMPTIONS.md`. These exist in the tree from the parallel track and were referenced only.

---
Last updated: 2026-05-17
MITRE ATT&CK: <https://attack.mitre.org/>
