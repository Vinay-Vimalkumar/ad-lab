# PHASE 3 STATUS

[2026-05-21 00:38:23 -04:00] STARTED: Phase 3 attacks 01-03. Baseline-clean snapshots confirmed from Phase 2. Creating pre-attack snapshots and artifact directories.
[2026-05-21 00:39:27 -04:00] SNAPSHOTS: pre-attack-01-03 attempted for all five Windows lab VMs. Artifact directories created.
[2026-05-21 00:39:53 -04:00] BRAAVOS PREFLIGHT: win_ping exit code 0.
[2026-05-21 00:41:25 -04:00] BRAAVOS PREP: ansible-playbook exit code 0.
[2026-05-21 00:41:52 -04:00] BRAAVOS TOOL VERIFY: exit code 0.
[2026-05-21 00:42:40 -04:00] RUBEUS DOWNLOAD RETRY: exit code 0.
[2026-05-21 00:43:56 -04:00] ATTACK EXECUTION: started parallel workers for Attack 01 BloodHound, Attack 02 Kerberoasting, and Attack 03 AS-REP roasting. Rubeus binary URL returned HTTP 404, so Impacket fallback is active for attacks 02/03 unless Rubeus is later found on braavos.
[2026-05-21 00:52:46 -04:00] ATTACK 02 COMPLETE: Kerberoasting completed with Impacket. Captured and validated hashes for svc_mssql, svc_web, svc_cifs, and svc_ldap. All validated as Password123!. Security Event ID 4769 with RC4 ticket encryption observed on kingslanding for root-domain service accounts.
[2026-05-21 00:52:46 -04:00] ATTACK 03 COMPLETE: AS-REP roasting completed with Impacket. Captured hashes for jon.snow, arya.stark, and sansa.stark. All validated as Password123!. Security Event ID 4768 with PreAuthType 0 observed on kingslanding.
[2026-05-21 00:54:08 -04:00] ATTACK 01: SharpHound playbook exit code 0.
[2026-05-21 00:57:59 -04:00] ATTACK 01: stdout capture playbook exit code 0.
[2026-05-21 00:58:16 -04:00] ATTACK 01: copied BloodHound outputs from ansible-control to host artifact directory; scp exit code 0.
[2026-05-21 00:59:23 -04:00] ATTACK 01: detection query playbook exit code 0.
[2026-05-21 00:59:46 -04:00] ATTACK 01 COMPLETE: BloodHound enumeration completed with SharpHound from braavos against sevenkingdoms.local and north.sevenkingdoms.local. BloodHound zips collected under attacks/artifacts/01-bloodhound. Sysmon Event ID 1 process-create telemetry verified on braavos; kingslanding Security 4662 records existed in the query window but were not cleanly attributable to SharpHound.

## Phase 3 Completion Summary

Status: PHASE 3 COMPLETE for attacks 01-03 only. Attacks 04-10 were not attempted.

Pre-attack snapshots created:

- ad-lab-kingslanding: pre-attack-01-03 UUID 5a3cbd78-c011-4d47-b80e-2aa4ac92cb2d
- ad-lab-castelblack: pre-attack-01-03 UUID 66a0ae45-ea0a-4239-bfb3-46af0400ba4f
- ad-lab-winterfell: pre-attack-01-03 UUID 5e10d1c2-f635-454d-9cc9-2857d5e882d6
- ad-lab-meereen: pre-attack-01-03 UUID 643becf0-8206-430d-b4a4-fbbd162a8711
- ad-lab-braavos: pre-attack-01-03 UUID fad59793-bc0b-4996-bcd7-ebc631d4458e

Artifacts:

- attacks/artifacts/01-bloodhound/results.md
- attacks/artifacts/01-bloodhound/detection-verified.md
- attacks/artifacts/02-kerberoasting/results.md
- attacks/artifacts/02-kerberoasting/detection-verified.md
- attacks/artifacts/03-asrep-roasting/results.md
- attacks/artifacts/03-asrep-roasting/detection-verified.md

Tooling notes:

- SharpHound.exe was downloaded and executed from C:\attacks on braavos.
- The requested Rubeus v2.3.2 binary URL returned HTTP 404, and official GhostPack guidance does not publish binaries, so Kerberoasting and AS-REP roasting used the authorized Impacket variants.
- Hashcat v6.2.5 was installed on ansible-control but failed on the CPU OpenCL backend due insufficient allocatable device memory; candidates from /tmp/adlab-wordlist.txt were validated through Kerberos/LDAP authentication checks and documented in each attack artifact.
