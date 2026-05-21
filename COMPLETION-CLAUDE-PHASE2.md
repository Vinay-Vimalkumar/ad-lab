# Completion Report — Claude (Phases 1 + 2, host/Vagrant lane)

**Date:** 2026-05-21 · **Final action:** baseline snapshots taken, lab handed off for Phase 3. Standing down.

---

## Final lab state — READY FOR PHASE 3 ✅

- **6 VMs running:** ad-lab-kingslanding, -castelblack, -winterfell, -meereen, -braavos, -ansible-control.
- **AD fully provisioned (Codex, Phase 2):** `sevenkingdoms.local` forest root (kingslanding) + `north.sevenkingdoms.local` child domain (winterfell) with trust; members joined (castelblack, meereen); braavos workstation; 25+ users, SPNs, AS-REP/delegation flags, vulnerable GPOs, ACL paths; Sysmon running on all 5 with baseline Event ID 1 captured.
- **`baseline-clean` snapshots on all 5 Windows VMs** (verified 5/5; ansible-control intentionally excluded).
- **Host:** native VirtualBox (VT-x; hypervisor/VBS off), ~3.4 GB RAM free with all 6 VMs up, 232.9 GB disk free.

## Snapshot UUIDs (baseline-clean)
| VM | UUID |
|----|------|
| ad-lab-kingslanding | 19e649c2-2297-4b38-85f2-42edbb6bcbe4 |
| ad-lab-castelblack | b56f50eb-cf09-49fc-a4c4-b9a69d511d77 |
| ad-lab-winterfell | f11aacb1-09e5-49f3-81bc-2db6d2ed71b8 |
| ad-lab-meereen | 33f973a2-5edd-4c2f-abfe-1025a024e1b6 |
| ad-lab-braavos | 463ddcc9-3762-4062-b5c3-bddd72921955 |

## What I did across the build

**Phase 0 (host):** disabled Hyper-V/VBS, installed VirtualBox 7.2.8 + Vagrant 2.4.9 (SHA256-verified), cached both boxes, fixed 2 Vagrantfile bugs.

**Phase 1 (bring-up):** diagnosed and fixed a chain of real issues, each from actual error output:
1. VirtualBox on the NEM/Hyper-V backend (too slow) → switched to native (Option B).
2. VBS/Memory Integrity re-armed the hypervisor across reboot → `vsmlaunchtype off` + disable VMPlatform/HVCI.
3–5. Three bootstrap bugs (Description >48 chars; account password complexity → decoupled connect vs account password; `\\labadmin$` regex mangled by Ruby heredoc).
6–7. braavos (Win10): WinRM 401 after hostname-rename reboot → skip Vagrant hostname; NAT adapter Public → set all NICs Private before WinRM config. Trimmed braavos to 2 GB for the host RAM budget.
Result: 5/5 Windows VMs up + WinRM reachable; aligned `vagrant`/`Administrator`/`labadmin` to `Password123!`.

**Phase 2 (standby + diagnostics + snapshots):**
- Monitored host health and PHASE2-STATUS.md without touching the mutable lab VMs.
- Caught and dismissed a false "PHASE 2 COMPLETE" (matched a planning line) — verified before acting.
- On the `child_domain` stall: read-only diagnosis pinpointed a stale/zombie WinRM socket from winterfell's promotion-reboot (ansible blocked on a dead connection; north domain not yet created). Reported to PHASE2-STATUS.md; did **not** intervene. Codex killed the hung run, added timeouts, re-ran, and completed the child DC.
- On real PHASE 2 COMPLETE: verified 6 VMs + live `north.sevenkingdoms.local`, took and verified the 5 `baseline-clean` snapshots, wrote the handoff + Phase 3 readiness summary.

## Phase 3 quick reference
- **Targets:** 192.168.56.10–14 (see PHASE2-STATUS.md for per-host roles).
- **Creds:** `vagrant` / `Administrator` / `labadmin` = `Password123!` on all Windows VMs.
- **Walkthroughs:** `/attacks/` (01–10). **Detections:** `/detection/kql-queries.md`.
- **Revert a VM:** `VBoxManage snapshot ad-lab-<name> restore baseline-clean` (poweroff first if running; start with `--type headless`). Restore only the five `ad-lab-*` Windows VMs.

## Notes / open items for Vinay
- Vagrantfile carries 7 host-lane fixes (all documented in PHASE1-STATUS.md). braavos memory is 2 GB (down from 4 GB) for the 32 GB host budget — revert if you add RAM.
- WSL2 is currently disabled (hypervisor off for native VirtualBox). To restore WSL2 later: `bcdedit /set hypervisorlaunchtype auto` + re-enable VirtualMachinePlatform + reboot (this re-introduces the VBox NEM slowdown — don't do it while running the lab).
- Ansible runs from the `ansible-control` VM (192.168.56.20), not host WSL2.

---

Claude standing down. Lab is at a clean, snapshotted baseline ready for Phase 3 attack execution.
Last updated: 2026-05-21
