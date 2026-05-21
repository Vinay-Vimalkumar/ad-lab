# Phase 2 Status

## Codex - Ansible Execution Lane

- `2026-05-20T02:20:09-04:00` - Phase 2 status initialized. Waiting for Phase 1 VM handoff.
- `2026-05-20T02:24:00-04:00` - Pre-staged Ansible collections against the repo-local `collections_path`; no changes needed because requested collections were already installed.
- `2026-05-20T02:24:00-04:00` - Added `GPMC` to root and child DC feature installation tasks so the later `vulnerable_gpos` role has the GroupPolicy module available.
- `2026-05-20T02:26:40-04:00` - Heartbeat: waiting for Claude Phase 1 VM handoff. No playbooks run against VMs yet.
- `2026-05-20T02:29:00-04:00` - Downloaded official Sysinternals `Sysmon.zip` to `infrastructure/provisioning/ansible/files/sysmon/Sysmon.zip`; SHA256 `9C7BBA9C88023ABD33188CFF4D3562278E0B7DDCCB7935B6A6530887F9E054B1`.
- `2026-05-20T02:29:00-04:00` - Added and validated `sysmon-deploy.yml` for controller-side Sysmon copy, signature check, install/update, service verification, and Event ID 1 baseline marker.
- `2026-05-20T02:31:00-04:00` - Heartbeat: still waiting for Claude Phase 1 VM handoff. No VM IPs are reachable from WSL yet.

## Role Progress

- common: pending
- forest_root: pending
- child_domain: pending
- domain_join: pending
- users_and_ous: pending
- service_accounts: pending
- asrep_accounts: pending
- delegation_accounts: pending
- vulnerable_gpos: pending
- acl_misconfigurations: pending
- sysmon_deployment: pending
- validation: pending

## Snapshot Signal

- Not ready. Baseline snapshots should wait until Codex marks Phase 2 complete.
- `2026-05-20T02:35:45.5375487-04:00` - Heartbeat: all five VM IPs now answer ping from WSL, but Codex is waiting for Claude's explicit Phase 1 completion marker before WinRM auth preflight.
- `2026-05-20T02:40:18.1230357-04:00` - Heartbeat: VM IPs remain reachable by ping, WinRM TCP 5985 not open yet, and Claude has not posted the Phase 1 completion marker. No playbooks run against VMs yet.
- `2026-05-20T02:44:40.4856760-04:00` - Heartbeat: Claude reports kingslanding running but WinRM HTTP not serving yet; Codex remains idle on playbook execution until Phase 1 completion marker.
- `2026-05-20T02:48:43.2511523-04:00` - Heartbeat: still waiting on Phase 1 handoff. Latest probes show ping reachable but WinRM 5985 closed; no Ansible playbooks have run against live VMs.
- `2026-05-20T02:53:50.8368241-04:00` - Heartbeat: Claude's latest status remains kingslanding first-boot WinRM wait. Codex probes still show ping reachable and TCP 5985 closed, so Phase 2 execution remains pending.
- `2026-05-20T02:56:41.4612104-04:00` - Heartbeat/correction: tightened WSL ping parsing. Latest corrected probe is: 192.168.56.10 ping down/5985 closed, 192.168.56.11 ping down/5985 closed, 192.168.56.12 ping down/5985 closed, 192.168.56.13 ping down/5985 closed, 192.168.56.14 ping down/5985 closed.
- `2026-05-20T02:58:34.7490732-04:00` - BLOCKED: Claude reports VirtualBox is running on the Hyper-V/NEM backend; kingslanding failed Vagrant boot_timeout, never served WinRM, and was destroyed cleanly. No Phase 2 playbooks were run. Waiting for user/Claude hypervisor decision before Ansible can proceed.
- `2026-05-20T02:59:09.3979263-04:00` - Wrote `PHASE2-CODEX-REPORT.md` documenting blocked state, pre-live validation, and that no Phase 2 roles or Sysmon deployment ran.
- `2026-05-20T15:22:39.4341473-04:00` - WSL check after Option B: `wsl --status` returned metadata and `wsl -d Ubuntu -- uname -a` launched successfully instead of failing. Proceeding with the requested VirtualBox-based Ansible control node anyway so Phase 2 does not depend on host WSL.
- `2026-05-20T15:23:40.7789876-04:00` - Added `ansible-control` VM design to `infrastructure/Vagrantfile`: Ubuntu 22.04 `ubuntu/jammy64`, static IP `192.168.56.20`, 2 vCPU, 2GB RAM, 20GB primary disk, synced `provisioning/ansible` to `/ansible`, and shell provisioner for Ansible, WinRM Python dependencies, and Windows/AD collections.
- `2026-05-20T15:23:40.7789876-04:00` - `vagrant validate` passed after adding the control node. Waiting for Claude marker `PHASE 1 COMPLETE: 5/5 VMs up` before bringing up `ansible-control` or running any VM-facing checks.
- `2026-05-20T15:25:00.1419885-04:00` - Phase 1 still blocked: Claude reports post-reboot hypervisor is still active because VBS/HVCI Memory Integrity re-armed it. Claude is applying VBS/hypervisor fixes and expects another reboot. Codex is holding `vagrant up ansible-control` until the true 5/5 VM marker appears.
- `2026-05-20T15:28:03.7527981-04:00` - Disabled host-side Ansible provisioner by default behind `AD_LAB_ENABLE_HOST_ANSIBLE=1` and guarded automatic Vagrant baseline snapshots behind `AD_LAB_ENABLE_VAGRANT_BASELINE_SNAPSHOT=1`. This keeps Phase 2 execution inside `ansible-control` only. `vagrant validate` passed again.
- `2026-05-20T15:30:22.5811975-04:00` - Phase 1 waiting on host reboot: Claude reports VBS/hypervisor disable is staged, `ADLab-Phase1-Resume` scheduled task is armed, and it will bring up only the five Windows VMs after next login. Codex will continue to wait for `PHASE 1 COMPLETE: 5/5 VMs up` before starting `ansible-control`.
- `2026-05-20T21:11:40.6566462-04:00` - PHASE 1 COMPLETE received from user. Starting Phase 2 control-node path. Bringing up only `ansible-control`; Windows VM access will occur only through Ansible from that node.
- `2026-05-20T21:14:58.9178945-04:00` - `ansible-control` is up at `192.168.56.20` with Ansible `2.17.14`. Fixed Sysmon playbook controller path by syncing `detection/sysmon-config.xml` into `/ansible/files/sysmon/sysmon-config.xml`.
- `2026-05-20T21:16:00.0751362-04:00` - `ansible-control` verification passed: IP `192.168.56.20`, Ansible `2.17.14`, collections available, `/ansible` mounted, inventory parsed with `vault_lab_password=Password123!`, and ICMP ping from control node to all five Windows VM IPs succeeded. Starting WinRM preflight.
- `2026-05-20T21:16:52.9760998-04:00` - Preflight connectivity passed from `ansible-control`: inventory metadata resolved, WinRM reachable, and `win_ping` ok on all five Windows VMs. Starting ordered role execution with `common`.
- `2026-05-20T21:19:12.5771511-04:00` - Role `common` completed successfully on all five VMs. `braavos` hostname changed/rebooted, and DNS/WinRM lab posture applied. Starting `forest_root` on `kingslanding`.
- `2026-05-20T21:25:38.5121337-04:00` - Role `forest_root` completed. Verified `sevenkingdoms.local` on `kingslanding` and confirmed `winterfell` can discover the root DC via `nltest /dsgetdc:sevenkingdoms.local`. Starting `child_domain`.

## [CLAUDE] READ-ONLY STALL DIAGNOSIS (child_domain) - 2026-05-20 ~22:10 ET
Requested by user. Nothing was restarted, killed, or mutated. All checks read-only.

**Summary: Phase 2 is STALLED on the `child_domain` role (winterfell). ansible is blocked on a stale/zombie WinRM connection; the north child domain was never created.**

Evidence:
1. **Playbook alive but hung:** on `ansible-control`, `ansible-playbook -i inventory.yml site.yml --tags child --limit winterfell` (PID 5382 + worker 5393) has etime ~51 min and is not progressing. Output goes to a tty (`/dev/pts/0`), not a log file. Not a zombie - genuinely blocked.
2. **No progress logged for ~42 min** (last status line 21:25:38 "Starting child_domain"). Host CPU ~1%, winterfell guest CPU ~0% (idle, not promoting).
3. **Root forest OK:** `kingslanding` resolves as `sevenkingdoms.local` DC (SRV + A .10). `common` and `forest_root` genuinely succeeded.
4. **north child domain does NOT exist:** querying `.12` and `.10` for `_ldap._tcp.dc._msdcs.north.sevenkingdoms.local`, `NS north.sevenkingdoms.local`, and `winterfell.north.sevenkingdoms.local` all return **Non-existent domain**. winterfell is NOT a DC. Promotion did not complete.
5. **winterfell is UP:** fresh `Test-WSMan 192.168.56.12` succeeds (WinRM service responsive). guestproperty shows LoggedInUsers=1, OS=Windows 2022, 2 NICs.
6. **Stale connection signature:** `ss` on the control node shows an **ESTABLISHED, idle (0/0) WinRM socket 192.168.56.20:40702 -> 192.168.56.12:5985**. ansible is blocked reading this socket while a *new* WinRM Identify works fine -> the pre-reboot connection is a zombie (winterfell rebooted during promotion; the old TCP session was never torn down). This matches the "win_reboot / promotion checking a stale connection" hypothesis (5c).
7. **Guest Additions control degraded:** `VBoxManage guestcontrol ad-lab-winterfell run ...` fails with `VERR_UNRESOLVED_ERROR` using BOTH local (vagrant) and domain (Administrator@north) creds - consistent with a pending/incomplete promotion / transitional state. (guestcontrol worked fine in Phase 1.)
8. **Host healthy:** RAM ~3.5 GB free, disk ~244 GB free, no resource exhaustion.

**Most likely root cause:** during winterfell's child-DC promotion the VM rebooted; ansible's pre-reboot WinRM TCP connection became a half-open zombie (still ESTABLISHED on the control node), and ansible is blocked in a read on that dead socket with no effective timeout -> indefinite hang. The promotion itself did not complete (north domain absent), so the role needs to actually run to completion.

**Recommended remediation (NOT performed - Codex/user lane):** interrupt the hung run in Codex's terminal (Ctrl-C) and re-run the child_domain role; `microsoft.ad.domain_controller` is idempotent and a fresh connection should proceed. Consider setting `ansible_winrm_read_timeout_sec` lower than the win_reboot poll and/or relying on the module's own reboot handling so a stale socket can't hang indefinitely. Claude remains in standby and will NOT intervene.
- `2026-05-20T22:24:25.6039187-04:00` - Killed stale `ansible-playbook` PIDs `5382` and `5393` on `ansible-control`. Updated WinRM timeouts to `operation=600s` and `read=900s` in `ansible.cfg` and `inventory.yml` so future dead sockets are bounded. Preparing child_domain rerun.
- `2026-05-20T22:25:15.2029136-04:00` - Re-ran `child_domain` as background PID `5828` inside `ansible-control` with output in `/ansible/child_domain-rerun.log`. Monitoring actively for reboot wait/stall.
- `2026-05-20T22:27:46.4527107-04:00` - Started child_domain rerun through host-side `vagrant ssh` wrapper PID `4008`. Stdout: `C:\Users\vinay\Downloads\ad-lab\logs\playbook-child_domain-rerun-20260520-222746.out.log`. Stderr: `C:\Users\vinay\Downloads\ad-lab\logs\playbook-child_domain-rerun-20260520-222746.err.log`. Monitoring begins now.
- `2026-05-20T22:28:08.3649103-04:00` - Restarted child_domain rerun wrapper with quoted remote command, host PID `15596`. Stdout: `C:\Users\vinay\Downloads\ad-lab\logs\playbook-child_domain-rerun-20260520-222808.out.log`. Stderr: `C:\Users\vinay\Downloads\ad-lab\logs\playbook-child_domain-rerun-20260520-222808.err.log`.
- `2026-05-20T22:28:57.0896528-04:00` - Child rerun failed fast with CredSSP public-key exchange on `winterfell`; no stall. Fresh `win_ping` using `ansible_winrm_transport=basic` succeeded, so rerunning `child_domain` with Basic transport override.
- `2026-05-20T22:29:05.7064885-04:00` - Started `child_domain` Basic-transport rerun, host wrapper PID `31208`. Stdout: `C:\Users\vinay\Downloads\ad-lab\logs\playbook-child_domain-basic-20260520-222905.out.log`. Stderr: `C:\Users\vinay\Downloads\ad-lab\logs\playbook-child_domain-basic-20260520-222905.err.log`.
- `2026-05-20T22:37:02.4497490-04:00` - Diagnosed child promotion failure as RPC 1722 caused by root DC DNS advertising NAT/IPv6 records. Cleaned `kingslanding` DNS registration so winterfell resolves the root DC only as `192.168.56.10`. Retrying `child_domain` with Basic transport.
- `2026-05-20T22:37:11.9289324-04:00` - Started second `child_domain` Basic retry after DNS cleanup, host wrapper PID `6656`. Stdout: `C:\Users\vinay\Downloads\ad-lab\logs\playbook-child_domain-basic-20260520-223711.out.log`. Stderr: `C:\Users\vinay\Downloads\ad-lab\logs\playbook-child_domain-basic-20260520-223711.err.log`.
- $ts - Heartbeat: resuming child_domain recovery. Stale local Ansible processes are gone; inspecting Winterfell promotion workers and DCPROMO mutex state from ansible-control before the next rerun.
- $ts - Recovery: killed stale Winterfell PowerShell workers 5288 and 3064 left by the failed child-domain attempt. Rerunning child_domain with Basic transport and bounded WinRM timeouts now.
- $ts - child_domain retry failed fast at the promotion task with no WinRM stall. Pulling Winterfell DCPROMO logs/process/service state to distinguish recoverable pending promotion from manual-promotion fallback.
- $ts - DCPROMO log on Winterfell reports child DC operation completed and wrote the pre-reboot locator hint. Proceeding with an Ansible-mediated Winterfell reboot, then validating 
orth.sevenkingdoms.local before any further role execution.
- $ts - Winterfell reboot after DCPROMO returned ebooted=true but timed out during Ansible post-reboot last-boot-time validation after 1800s. Probing fresh WinRM with post-promotion credentials now.
- $ts - child_domain recovered: Winterfell is now 
orth.sevenkingdoms.local, AD DS services are running, Get-ADDomain succeeds, and 
ltest /domain_trusts shows the parent-child trust. Completing child post-promotion cleanup/admin tasks next.
- $ts - Winterfell post-promotion cleanup partially ran. Optional Set-DnsServerSetting -ListenAddresses is unsupported on this image, so rerunning cleanup without that parameter and continuing child labadmin creation.
- $ts - Completed child post-promotion recovery: child DNS cleanup ran, labadmin exists in 
orth.sevenkingdoms.local, and ADSI confirmed it is in NORTH\Domain Admins. Testing domain admin WinRM before remaining roles.
- $ts - Patched Ansible code for durable DC DNS cleanup and post-promotion Administrator credentials. site.yml --syntax-check passed. Starting domain_join for castelblack, meereen, and braavos.
- $ts - Role domain_join completed successfully on castelblack, meereen, and braavos; all three rebooted after joining their assigned domains. Running join verification, then identity roles.
- $ts - Diagnosed identity failure as missing guest provisioning scripts. Patched common to copy scripts from /vagrant/provisioning/scripts to C:\infrastructure\provisioning\scripts; syntax check still passes. Copying scripts to DCs live now.
- $ts - Moved guest script root to C:\LabProvisioning, copied provisioning scripts to both DCs, and syntax check passed. Retrying identity roles now.
- $ts - Patched create-users.ps1 idempotency for missing OUs and same-domain group membership; verified user/OUs provisioning succeeds in both domains. Retrying full identity roles.
- $ts - Role set identity completed successfully on kingslanding and winterfell: users/OUs, service accounts/SPNs, AS-REP flags, and delegation flags all ran. Starting ulnerabilities roles (ulnerable_gpos, cl_misconfigurations).
- $ts - Role ulnerable_gpos completed on both domains after PSO idempotency patch; role cl_misconfigurations completed on kingslanding after array-argument wrapper fix. Running one clean combined vulnerabilities pass.
- $ts - Clean combined ulnerabilities pass completed successfully. Running AD validation checks for trust, users, SPNs, UAC flags, delegation flags, joins, and GPO counts.
- $ts - Validation pass confirms forests/trusts, joined members, user/SPN/UAC/GPO state. Administrator WinRM works on all five VMs. Starting sysmon-deploy.yml on all Windows hosts.
- $ts - First Sysmon deploy copied/extracted files and validated config but failed during native executable invocation. Patched sysmon-deploy.yml to call Sysmon via Start-Process and preserve exit-code handling. Retrying deployment.
- $ts - Sysmon deployment completed successfully on all five VMs and generated baseline Event ID 1 markers. Running final targeted verification pass and preparing Phase 2 report.
- $ts - PHASE 2 COMPLETE: all roles executed successfully after recovery, validation passed, Sysmon is running on all five VMs, and baseline Event ID 1 events were captured.
- $ts - SNAPSHOT HANDOFF: Claude can take baseline snapshots now.

## [CLAUDE] PHASE 2 SNAPSHOTS TAKEN - baseline-clean on all 5 lab VMs at 00:25 (2026-05-21). Lab ready for Phase 3 (attack execution).

Verified before snapshotting: 6 VMs running (5 Windows + ansible-control); genuine PHASE 2 COMPLETE marker; `north.sevenkingdoms.local` child domain live (winterfell = child DC, SRV/A resolve).

baseline-clean snapshots (VBoxManage, online incl. memory state), all verified present (5/5):
- ad-lab-kingslanding  UUID 19e649c2-2297-4b38-85f2-42edbb6bcbe4
- ad-lab-castelblack   UUID b56f50eb-cf09-49fc-a4c4-b9a69d511d77
- ad-lab-winterfell    UUID f11aacb1-09e5-49f3-81bc-2db6d2ed71b8
- ad-lab-meereen       UUID 33f973a2-5edd-4c2f-abfe-1025a024e1b6
- ad-lab-braavos       UUID 463ddcc9-3762-4062-b5c3-bddd72921955
(ansible-control intentionally NOT snapshotted - tooling, not a target.) Disk free after: 232.9 GB.

### Phase 3 readiness summary
- **Targets (host-only 192.168.56.0/24):**
  - 192.168.56.10  kingslanding  - sevenkingdoms.local forest root DC
  - 192.168.56.11  castelblack   - sevenkingdoms.local member server
  - 192.168.56.12  winterfell    - north.sevenkingdoms.local child DC
  - 192.168.56.13  meereen       - north.sevenkingdoms.local member server
  - 192.168.56.14  braavos       - sevenkingdoms.local Windows 10 workstation
- **Credentials (lab):** local accounts `vagrant`, `Administrator`, and `labadmin` are all **Password123!** on every Windows VM. Domain admins per design: `tywin.lannister` (sevenkingdoms), `eddard.stark` (north) - also Password123! per lab convention.
- **Attack walkthroughs:** `/attacks/` (01 BloodHound -> 10 cross-forest trust abuse). Detection queries: `/detection/kql-queries.md`.
- **Revert a VM to clean state:** `VBoxManage controlvm ad-lab-<name> poweroff` (if needed) then `VBoxManage snapshot ad-lab-<name> restore baseline-clean` then `VBoxManage startvm ad-lab-<name> --type headless`. Restore-all is just the five `ad-lab-*` Windows VMs; leave ansible-control as-is.
- **Attacker tooling:** run from `ansible-control` (192.168.56.20) or the host; Impacket/Rubeus/etc. per `/attacks/` prerequisites.
