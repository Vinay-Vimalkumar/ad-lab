# Phase 1 Status

## Codex - Ansible Lane

- `2026-05-20T02:20:09-04:00` - Phase 1 Ansible prep started. `PHASE1-STATUS.md` did not exist, so Codex created it.
- `2026-05-20T02:20:13-04:00` - Verified WSL Ansible environment and inventory graph. Output is logged to `logs/phase1-codex.log`.
- `2026-05-20T02:21:08-04:00` - Initial WSL ping probe to `192.168.56.10` through `192.168.56.14` returned 100% packet loss for all five IPs, expected while Claude is still bringing VMs up.
- `2026-05-20T02:21:xx-04:00` - `ansible-playbook --syntax-check` passed for `site.yml` and `preflight-connectivity.yml`; `ansible-lint` passed at production profile.
- `2026-05-20T02:25:xx-04:00` - Codex confirms Claude's WinRM credential alignment plan. Keep Ansible inventory unchanged as `vagrant / Password123!`; Claude may bring stock boxes up with `vagrant / vagrant`, then align `vagrant`, `Administrator`, and `labadmin` to `Password123!` on all five VMs before Codex WinRM preflight.
- `2026-05-20T02:25:49-04:00` - WSL ping sweep still reports all five future VM IPs down.
- Waiting for Claude status phrase: `PHASE 1 COMPLETE: 5/5 VMs up`.

## Claude - Vagrant Lane

### Pre-flight (02:20) — PASSED with one caveat
- ✅ VirtualBox `7.2.8r173730`, Vagrant `2.4.9`; boxes cached (`windows-server-2022-standard` 2601.0.0, `windows-10` 2511.0.0)
- ✅ Host-only adapter present at `192.168.56.1`; VBox 7 default allows `192.168.56.0/21` (no `networks.conf` needed); disk 345 GB free
- ⚠️ **RAM: 17.2 GB free vs 18 GB requested by 5 VMs.** Host baseline ~14.7 GB. VMs boot sequentially so peak is reached only at VM #5; expect some paging. Proceeding per "report + continue if survivable"; will monitor and report.
- Vagrantfile timeouts generous (boot 1800s, WinRM 90×10s) — good for slow coexistence mode.

### ⚠️ [CLAUDE → CODEX] WinRM credential model — please confirm
The base box ships with Vagrant's stock WinRM creds **`vagrant / vagrant`** (embedded Vagrantfile doesn't override the password). Therefore:
1. For the **initial** `vagrant up` to connect, **`AD_LAB_WINRM_PASSWORD` must = `vagrant`** (setting it to `Password123!` fails the first connect → 90 retries → bootstrap never runs). This overrides the literal "set Password123!" instruction — it's empirically required by the stock box.
2. The Vagrant bootstrap sets **Administrator + labadmin** to that same value; it does **not** change the `vagrant` account.
3. Your `inventory.yml` connects as **`vagrant / Password123!`** and expects `labadmin = Password123!`.

**Gap:** after a stock up, local accounts are `vagrant`, not `Password123!` → your `vagrant/Password123!` connect would fail.

**Claude's resolution (no edits to your files):** bring VMs up with `AD_LAB_WINRM_PASSWORD=vagrant`, then run an idempotent step setting **vagrant + Administrator + labadmin → Password123!** on all 5 VMs so your inventory connects unchanged. After that, further host `vagrant` ops use `AD_LAB_WINRM_PASSWORD=Password123!`. If you'd rather your first play own the password change, note it here and Claude will skip the alignment.

### VM bring-up progress
| VM | IP | Booted | WinRM 5985 | Pwd-aligned | Notes |
|----|----|--------|-----------|-------------|-------|
| kingslanding | 192.168.56.10 | — | — | — | up first (end-to-end validation) |
| castelblack | 192.168.56.11 | — | — | — | |
| winterfell | 192.168.56.12 | — | — | — | |
| meereen | 192.168.56.13 | — | — | — | |
| braavos | 192.168.56.14 | — | — | — | |

- `[CLAUDE] 02:22` — Decision logged; starting `vagrant up kingslanding` with `AD_LAB_WINRM_PASSWORD=vagrant`.
- `2026-05-20T02:33:44.5882616-04:00` - WSL ping sweep still reports all five VM IPs down; continuing to wait for Claude handoff.
- `2026-05-20T02:35:17.6372511-04:00` - WSL ping sweep: 192.168.56.10 reachable, 192.168.56.11 reachable, 192.168.56.12 reachable, 192.168.56.13 reachable, 192.168.56.14 reachable.
- `2026-05-20T02:37:35.3307143-04:00` - WSL ping sweep: 192.168.56.10 reachable, 192.168.56.11 reachable, 192.168.56.12 reachable, 192.168.56.13 reachable, 192.168.56.14 reachable.
- `2026-05-20T02:39:19.4060481-04:00` - Non-auth WSL TCP probe: 192.168.56.10 5985 closed, 192.168.56.11 5985 closed, 192.168.56.12 5985 closed, 192.168.56.13 5985 closed, 192.168.56.14 5985 closed.
- `2026-05-20T02:41:34.7788300-04:00` - WSL readiness probe: 192.168.56.10 ping reachable/5985 closed, 192.168.56.11 ping reachable/5985 closed, 192.168.56.12 ping reachable/5985 closed, 192.168.56.13 ping reachable/5985 closed, 192.168.56.14 ping reachable/5985 closed.
- `[CLAUDE] 02:44` — kingslanding running; WinRM HTTP not yet serving (returns no HTTP response, not a 401 → not auth). Likely still in first-boot OOBE/specialize under slow coexistence mode. RAM ~11-13GB free with 1 VM (no paging for a single 4GB VM). Continuing to wait within boot_timeout=1800s.
- `2026-05-20T02:45:19.7921129-04:00` - WSL readiness probe: 192.168.56.10 ping reachable/5985 closed, 192.168.56.11 ping reachable/5985 closed, 192.168.56.12 ping reachable/5985 closed, 192.168.56.13 ping reachable/5985 closed, 192.168.56.14 ping reachable/5985 closed.
- `2026-05-20T02:47:37.1753084-04:00` - WSL readiness probe: 192.168.56.10 ping reachable/5985 closed, 192.168.56.11 ping reachable/5985 closed, 192.168.56.12 ping reachable/5985 closed, 192.168.56.13 ping reachable/5985 closed, 192.168.56.14 ping reachable/5985 closed.
- `2026-05-20T02:49:23.0619719-04:00` - WSL readiness probe: 192.168.56.10 ping reachable/5985 closed, 192.168.56.11 ping reachable/5985 closed, 192.168.56.12 ping reachable/5985 closed, 192.168.56.13 ping reachable/5985 closed, 192.168.56.14 ping reachable/5985 closed.
- `2026-05-20T02:51:03.8817667-04:00` - WSL readiness probe: 192.168.56.10 ping reachable/5985 closed, 192.168.56.11 ping reachable/5985 closed, 192.168.56.12 ping reachable/5985 closed, 192.168.56.13 ping reachable/5985 closed, 192.168.56.14 ping reachable/5985 closed.
- `2026-05-20T02:52:45.8759826-04:00` - WSL readiness probe: 192.168.56.10 ping reachable/5985 closed, 192.168.56.11 ping reachable/5985 closed, 192.168.56.12 ping reachable/5985 closed, 192.168.56.13 ping reachable/5985 closed, 192.168.56.14 ping reachable/5985 closed.
- `2026-05-20T02:55:54.7500568-04:00` - WSL readiness probe: 192.168.56.10 ping reachable/5985 closed, 192.168.56.11 ping reachable/5985 closed, 192.168.56.12 ping reachable/5985 closed, 192.168.56.13 ping reachable/5985 closed, 192.168.56.14 ping reachable/5985 closed.
- `2026-05-20T02:56:41.4612104-04:00` - Corrected WSL readiness probe: 192.168.56.10 ping down/5985 closed, 192.168.56.11 ping down/5985 closed, 192.168.56.12 ping down/5985 closed, 192.168.56.13 ping down/5985 closed, 192.168.56.14 ping down/5985 closed. Earlier 'reachable' lines may include false positives from matching '100% packet loss'.

## 🛑 [CLAUDE] BLOCKER — VirtualBox is on the NEM (Hyper-V coexistence) backend; guests too slow to boot

- `vagrant up kingslanding` ran 30 min and **failed at boot_timeout** — the Windows Server guest never served WinRM (HTTP returned no response the entire time, not a 401, so not an auth issue). VM used a steady ~12% host CPU the whole time (grinding, not idle).
- **VBox.log proof:** `HM: HMR3Init: Attempting fall back to NEM: VT-x is not available` + `NEM: WHvCapabilityCodeHypervisorPresent is TRUE`. VirtualBox is running **on top of Hyper-V via NEM** because the Hyper-V hypervisor (kept for WSL2 under Option A) owns VT-x. This is the documented 5–20× slowdown — too slow to provision Windows DCs.
- There is **no software fix within Option A**: as long as `hypervisorlaunchtype` is on / `VirtualMachinePlatform` is enabled, VBox cannot get native VT-x and stays on NEM.
- Stuck VM powered off and destroyed; host clean (16.8 GB free, 0 running VMs).
- **Escalated to user**: choose Option B (native VBox — disable VirtualMachinePlatform + `hypervisorlaunchtype off` + reboot; breaks WSL2/Ansible-on-host) vs. tolerate extreme slowness. Phase 1 is paused pending that decision. Codex: hold — do not expect VMs until this is resolved.

## ✅→🔄 [CLAUDE] Option B applied — REBOOT REQUIRED to finish Phase 1

- User chose **Option B (native VirtualBox)**. Applied `bcdedit /set hypervisorlaunchtype off` (verified: `hypervisorlaunchtype Off`). Combined with the Phase-0 staged VBS-off, the Hyper-V hypervisor will **not** load at next boot, freeing VT-x so VirtualBox runs natively (HM, not NEM).
- **A reboot is required** and it kills this Claude session (my process runs on the host). I did **not** force the reboot so the user can save work and coordinate.

### ⚠️ [CLAUDE → CODEX] WSL2 will STOP working after the reboot
- With `hypervisorlaunchtype off`, WSL2 (and any Hyper-V VM) will not start until it's reverted (`bcdedit /set hypervisorlaunchtype auto` + reboot). **Your Ansible-on-WSL2 control node will be unavailable.**
- For Phase 2 you'll need a control node that runs under native VBox — e.g. a small Ubuntu VirtualBox guest on the `192.168.56.0/24` host-only network, or another Linux host. Flagging now so you can plan; this is your lane.

### Post-reboot resume (Claude will run with monitoring when re-engaged)
1. Verify native mode: `systeminfo | Select-String "hypervisor"` should **no longer** say "A hypervisor has been detected".
2. Bring up + password-align in one step: `powershell -ExecutionPolicy Bypass -File C:\Users\vinay\Downloads\ad-lab\logs\phase1-resume.ps1` (brings up all 5 with `AD_LAB_WINRM_PASSWORD=vagrant`, then sets vagrant/Administrator/labadmin → Password123! via Guest Additions).
3. Verify each VM reachable on WinRM 5985 (host-only), then signal Codex: `PHASE 1 COMPLETE: 5/5 VMs up`.

**STATUS: Phase 1 paused at reboot boundary. Boxes cached, Vagrantfile valid, hypervisor disabled. Resume after reboot.**

## 🛑→🔧 [CLAUDE] Resume attempt 1: hypervisor STILL on after reboot — root cause = VBS/Memory Integrity

- Post-reboot (uptime 9 min) `systeminfo` still reports "A hypervisor has been detected"; `hypervisorlaunchtype` reverted to default (Auto).
- **Win32_DeviceGuard: VBS status = 2 (RUNNING), SecurityServicesRunning = 2 (HVCI / Memory Integrity).** HVCI registry `Enabled`=1 (re-armed since Phase 0).
- Diagnosis: **VBS/Memory Integrity forces the hypervisor to load at boot and resets `hypervisorlaunchtype`**, so VBox stays on the slow NEM backend. `hypervisorlaunchtype off` alone is insufficient — VBS must be disabled too.
- Fix being applied (elevated): `bcdedit /set vsmlaunchtype off` + `hypervisorlaunchtype off`, HVCI/VBS registry → 0, disable VirtualMachinePlatform + Hyper-V role. Requires another reboot. If VBS re-arms again after this, it's a UEFI-locked / UI-managed Memory Integrity toggle that must be turned off in Windows Security → Core Isolation (will guide user).

## ✅ [CLAUDE] VBS disabled — reboot will give native VirtualBox; auto-resume armed

- **Root fix applied (elevated, verified):** `hypervisorlaunchtype = Off`, `vsmlaunchtype = Off`, **VirtualMachinePlatform disabled**, HVCI/VBS registry zeroed. (Hyper-V role + HypervisorPlatform were already off.) After the next reboot the hypervisor will NOT load → VirtualBox gets native VT-x (HM, not NEM).
- **Auto-resume scheduled task `ADLab-Phase1-Resume` registered** (ONLOGON, current user). On next login it runs `logs/phase1-resume.ps1`, which:
  1. **Guards**: if a hypervisor is still detected (VBS somehow survived), it ABORTS instead of wasting 30 min on slow NEM, and writes the reason here.
  2. `vagrant up` the **5 Windows VMs only** (kingslanding, castelblack, winterfell, meereen, braavos) with `AD_LAB_WINRM_PASSWORD=vagrant` — does NOT touch Codex's new `ansible-control` (ubuntu/jammy64 @ .20) node.
  3. Aligns vagrant/Administrator/labadmin → `Password123!` via Guest Additions.
  4. Verifies WinRM 5985 on .10–.14 and writes `PHASE 1 COMPLETE: 5/5 VMs up` here if all reachable.
  5. Self-deletes the task.
- Output logs to `logs/phase1-resume-attempt2.log`.

### 👉 USER ACTION: reboot the host now
A reboot is required to apply the VBS/hypervisor disable (it kills this Claude session). After you log back in, the lab builds itself via the task — no need to re-engage me unless it reports a problem here. If the guard aborts (hypervisor survived), it means Memory Integrity is UI/UEFI-locked: turn it off manually in **Windows Security → Device security → Core isolation → Memory integrity = Off**, reboot again, and the task will complete.

- `[CLAUDE] 18:47` User issued Restart-Computer. Rebooting to apply VBS/hypervisor disable; auto-resume task ADLab-Phase1-Resume will run at next logon. This Claude session ends here.

## ? [CLAUDE] Native mode CONFIRMED after reboot (18:48 boot)
- hypervisor detected: False ; VBS status: 0 (off). VirtualBox now gets native VT-x.
- Unregistered ONLOGON task to avoid races; Claude running `phase1-resume.ps1` directly with monitoring at 18:50.
- [CLAUDE-RESUME] 19:01 Phase 1 partial: reachable=kingslanding unreachable=castelblack,winterfell,meereen,braavos. Diagnose needed.

## [CLAUDE -> CODEX] Bug #3 fixed in Vagrantfile bootstrap (was blocking ALL provisioning)
- The `bootstrap-winrm-lab-only` shell provisioner failed on every VM at `New-LocalUser -Description "Local bootstrap admin promoted into the lab domain when applicable"` — that string is 66 chars, but `-Description` max is 48. With `$ErrorActionPreference='Stop'`, this aborted the whole bootstrap (so WinRM/Basic/CredSSP/firewall config and password set never ran), and `vagrant up` aborted after the first VM.
- This (not a splat bug) is why earlier only kingslanding was created and its WinRM was reachable only via the box's default listener.
- **Fix applied by Claude:** shortened to `-Description "AD lab bootstrap admin"` (22 chars). `vagrant validate` passes.
- Re-running `vagrant up --provision` on all 5 Windows VMs now (native mode). Logs: `logs/phase1-bringup-all.log`.

## [CLAUDE -> CODEX] Bug #4 fixed: bootstrap account password failed complexity
- After the Description fix, `New-LocalUser` for labadmin failed with InvalidPasswordException ("does not meet length, complexity, or history requirements"). Cause: the bootstrap set the account password to `AD_LAB_BOOTSTRAP_PASSWORD` = `winrm_password` = "vagrant" (the stock box connect password), which is too weak to create a local user.
- **Fix (decouple connect vs account password):** added `bootstrap_account_password = ENV.fetch("AD_LAB_ACCOUNT_PASSWORD", "Password123!")` and changed the provisioner env to use it. Vagrant still CONNECTS with stock `vagrant`/`vagrant` (AD_LAB_WINRM_PASSWORD=vagrant); the bootstrap now SETS Administrator/labadmin to the complex `Password123!`. `vagrant validate` passes.
- Net effect for Codex: after provisioning, **labadmin = Password123!** already (matches your group_vars). Claude's post-provision align then sets the **vagrant** account to Password123! too, so your inventory `vagrant/Password123!` connects. Re-running `vagrant up --provision` now; log `logs/phase1-bringup-all2.log`.

## [CLAUDE -> CODEX] Bug #5 fixed: regex backslash mangled by Ruby heredoc
- Bootstrap line ~138 `Where-Object { $_.Name -match "\labadmin$" ... }` failed: "Unrecognized escape sequence \l". The interpolating Ruby heredoc (`<<-POWERSHELL`) collapses `\` -> `\`, so the guest received `-match "\labadmin$"` (invalid PS regex). (The WSMan `\localhost\...` paths are unaffected since single `\` is correct there.)
- **Fix:** changed regex to `-match "labadmin$"` (no backslash; still matches `COMPUTER\labadmin`). Audited the entire bootstrap heredoc for other `\`/escape issues - this was the only one.
- Re-running `vagrant up --provision` (bv6i9ronn); log `logs/phase1-bringup-all3.log`. Bugs #3/#4/#5 were all in the bootstrap provisioner (untested against a live Windows guest).

## [CLAUDE] 4/5 up; braavos failed on the memory ceiling -> reduced to 2GB
- 4 servers (kingslanding/castelblack/winterfell/meereen) are UP and WinRM-reachable (.10-.13:5985 = True), all bootstrapped cleanly after bug fixes #3-#5.
- braavos (5th VM) failure: booted + first WinRM ok, then `Setting hostname` reboot -> reconnect threw `WinRMAuthorizationError`; vagrant rolled back/destroyed it. Root cause = the host RAM ceiling flagged in pre-flight (17.2 GB free vs 18 GB for 5 VMs): with 4 servers using ~14 GB and only ~4 GB free, braavos's post-rename reboot thrashed and WinRM didn't recover before retry exhaustion.
- **Deviation (resource-driven, reversible):** reduced braavos memory 4096 -> 2048 MB in Vagrantfile (Win10 workstation runs fine at 2 GB for lab use). Keeps total VM commit ~16 GB so the host (32 GB, ~14 GB baseline) isn't maxed. Re-running braavos now (bbp6sdi52). If full 4 GB is desired later, close host apps / raise host RAM and revert.

## [CLAUDE -> CODEX] Bug #6 / workaround: Win10 box fails Vagrant hostname-rename (WinRM 401)
- Reducing braavos RAM did NOT fix it (so not memory). Real cause: on `gusztavvargadr/windows-10` (2511.0.0), Vagrant's `Setting hostname` renames the PC and reboots; on reconnect WinRM returns `WinRMAuthorizationError` (401) and vagrant rolls back/destroys the VM. Server 2022 boxes survive the same step; the Win10 box does not.
- **Workaround in Vagrantfile:** `node.vm.hostname = name unless name == "braavos"` — skip Vagrant's hostname step for braavos. **Codex: please set braavos's hostname to BRAAVOS during Ansible provisioning** (your inventory already has lab_hostname=BRAAVOS), since Vagrant no longer does it.
- braavos memory left at 2048 MB (helps the 5-VM RAM budget regardless). Re-running braavos now (br219i86g).

## [CLAUDE -> CODEX] Bug #7 fixed: bootstrap aborted on Public NAT profile (Win10)
- With hostname skipped, braavos reached the bootstrap but failed: "Set-Item : WinRM firewall exception will not work since one of the network connection types ... is set to Public" (ErrorActionPreference=Stop -> abort). braavos's NAT adapter is on the Public profile; the bootstrap only set the 192.168.56.* adapter to Private.
- **Fix:** added `Get-NetConnectionProfile | Set-NetConnectionProfile -NetworkCategory Private` (all adapters incl. NAT) before the WinRM/firewall config. Harmless for the servers; required for the Win10 box. Re-running braavos (bahqf4q5u).

## PHASE 1 COMPLETE: 5/5 VMs up and reachable at 20:49. Ready for Phase 2.

- kingslanding (192.168.56.10), castelblack (.11), winterfell (.12), meereen (.13), braavos (.14): **all running, WinRM 5985 reachable (5/5)**, native VirtualBox (VT-x, no NEM).
- **Credentials for Codex's Ansible:** local accounts `vagrant`, `Administrator`, `labadmin` are all set to **Password123!** on every VM (vagrant aligned via Guest Additions; Administrator/labadmin set by the fixed bootstrap). Verified `vagrant/Password123!` authenticates on all 5. Inventory (`vagrant`/`Password123!`, WinRM CredSSP) should connect unchanged.
- **For Codex:** braavos hostname is still the box default (`DESKTOP-I806MQL`) because Vagrant's hostname-rename was skipped (Win10 WinRM-401 workaround, bug #6). Please set it to BRAAVOS during provisioning.
- Vagrantfile fixes applied this phase (all flagged above): #3 Description>48, #4 account-password complexity (decoupled connect vs account pwd; AD_LAB_ACCOUNT_PASSWORD default Password123!), #5 regex backslash, #6 skip hostname for braavos, #7 set all NICs Private before WinRM config. braavos memory 4096->2048 (host RAM budget).
- Host: native mode (hypervisorlaunchtype off, VBS off); ~5-6 GB RAM free with all 5 running.
