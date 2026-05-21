# Phase 0 Status

## Codex - WSL2 / Ubuntu / Ansible Lane

- Status file was missing at Codex start, so this coordination file was created.
- Read `docs/00-environment-setup.md`.
- Current shell is not elevated, so direct Windows optional-feature inspection requires admin/UAC.
- `wsl --status` reports default distribution `Ubuntu` and default version `2`.
- `wsl --list --verbose` shows `Ubuntu` and `kali-linux`, both WSL version `2`.
- Existing `Ubuntu` distro is Ubuntu 22.04.3 LTS with default user `vinay`.
- WSL package reports version `2.7.3.0`; kernel reports `6.6.114.1`.
- Ansible already exists in the `vinay` user-local Python path from prior validation work: `ansible-core 2.17.14`.
- Existing collections found: `ansible.windows 3.5.0`, `community.windows 3.1.0`, `microsoft.ad 1.10.0`.
- Ran `apt-get update` and `apt-get upgrade -y` inside Ubuntu as root.
- Apt upgrade completed; Ubuntu kept back `libnetplan0`, `netplan.io`, `ubuntu-advantage-tools`, `ubuntu-pro-client-l10n`, `ubuntu-wsl`, and `wsl-setup`.
- Installed/confirmed `software-properties-common` and `python3-pip`.
- Added the Ansible Ubuntu PPA `ppa:ansible/ansible`.
- Installed Ubuntu packages `ansible` and `ansible-core` from the Ansible PPA.
- Installed/upgraded user-local Python `pywinrm` to `0.5.0`.
- Confirmed Ansible collections are installed: `ansible.windows`, `community.windows`, and `microsoft.ad`.
- Ran `wsl --set-default-version 2`; command completed successfully.
- Verified WSL networking: Ubuntu has NAT address `172.25.193.30/20`, default route `172.25.192.1`, can ping `8.8.8.8`, and resolves `archive.ubuntu.com`.
- Ran `ansible-playbook --syntax-check -i inventory.yml site.yml -e vault_lab_password='Password123!'` from inside WSL; syntax check passed.
- Follow-up readiness pass: installed `requests-credssp 2.0.0` and `pyspnego 0.12.1` so the inventory's `ansible_winrm_transport: credssp` can authenticate when VMs exist.
- Added `infrastructure/provisioning/ansible/preflight-connectivity.yml` for Phase 1 inventory and WinRM/auth readiness checks.
- Restored `infrastructure/provisioning/ansible/group_vars/all/main.yml` so Ansible loads shared lab variables from the active `group_vars/all/` directory layout.
- Inventory dry run passed for all five hosts with resolved targets:
  - `kingslanding` -> `192.168.56.10:5985`, WinRM CredSSP, `sevenkingdoms.local`
  - `castelblack` -> `192.168.56.11:5985`, WinRM CredSSP, `sevenkingdoms.local`
  - `winterfell` -> `192.168.56.12:5985`, WinRM CredSSP, `north.sevenkingdoms.local`
  - `meereen` -> `192.168.56.13:5985`, WinRM CredSSP, `north.sevenkingdoms.local`
  - `braavos` -> `192.168.56.14:5985`, WinRM CredSSP, `sevenkingdoms.local`
- Expected-fail WinRM auth probe reached the CredSSP WinRM code path for all five future VM IPs and failed only with `No route to host`, which is expected before `vagrant up` creates the VMs/host-only network.
- `ansible-playbook --syntax-check` passed for both `site.yml` and `preflight-connectivity.yml`.
- `ansible-lint site.yml preflight-connectivity.yml` passed at the production profile.
- Codex did not edit `infrastructure/Vagrantfile`; Claude owns the two known Vagrantfile fixes.

## Idle State

- Codex WSL2/Ubuntu/Ansible lane is idle and ready for Phase 1.
- Next Codex action after `vagrant up`: run the preflight auth playbook, then proceed with provisioning validation if WinRM responds.

## Coordination Notes

- Claude Hyper-V/VirtualBox/Vagrant status was not present when Codex started this phase.
- Codex will not duplicate Claude's Windows host lane.
- Because WSL2 and Ubuntu already exist and run, Codex is continuing with Ubuntu/Ansible configuration that does not require a Windows reboot.
- After Claude updated this file, Codex observed Claude's decision to keep WSL2 live and not force a reboot while Codex is working.
- Codex did not install a duplicate `Ubuntu-22.04` distro because the existing default `Ubuntu` distro is already Ubuntu 22.04.3 LTS with user `vinay`.
- No temporary WSL default password was created or stored because first-launch user setup had already been completed before this phase.

## Claude - Windows Host Lane

### Initial host state (captured 2026-05-20)
- Agent shell **not elevated** — using `Start-Process -Verb RunAs` for admin steps (one UAC prompt for the user).
- Hyper-V hypervisor **ACTIVE**: `systeminfo` reports "A hypervisor has been detected."
- Hyper-V services: `hvhost` Running (Manual), `vmcompute` Running (Manual), `vmms` absent.
- **VirtualBox not installed**; **Vagrant not installed**; **winget unavailable** → using direct downloads.
- Disk free (C:): 366 GB. Internet: OK.
- Latest stable resolved: **VirtualBox 7.2.8** (build 173730), **Vagrant 2.4.9**.

### IMPORTANT coordination decision — Hyper-V vs WSL2 (do not break Codex)
- Codex's WSL2/Ubuntu is **live**. WSL2 requires `VirtualMachinePlatform` + the boot-time hypervisor. VirtualBox 7.x native speed requires the hypervisor **off**. These are mutually exclusive (see `docs/00-environment-setup.md` §0).
- **Decision:** I will NOT disable `VirtualMachinePlatform` and will NOT set `hypervisorlaunchtype off` — both would break Codex's WSL2. I will stage disable of only the heavyweight Hyper-V *role* + VBS (Credential Guard / HVCI / Device Guard / Windows Sandbox) with `-NoRestart`, which WSL2 does not need. VirtualBox will run in **Hyper-V coexistence ("slow") mode** while WSL2 stays up — functional for build/validate.
- **I will NOT force a reboot** while Codex is working. The reboot (to apply feature changes) is documented as a coordinated step for the user to trigger.
- All my Phase 0 deliverables (install VBox/Vagrant, PATH, box cache, `vagrant validate`) complete **without** a reboot. Native-speed-vs-WSL2 is flagged as a user decision in `PHASE0-CLAUDE-REPORT.md`.

### Progress
- `[CLAUDE] 2026-05-20` — State assessed; latest versions resolved (VBox 7.2.8, Vagrant 2.4.9). Downloading + SHA256-verifying installers next.
- `[CLAUDE] 2026-05-20` — Installers SHA256-verified against published sums: VirtualBox `ae5415cc…1606` ✓, Vagrant MSI `3bdd9679…cbe3` ✓.
- `[CLAUDE] 2026-05-20` — Elevated run OK (exit 0). **Finding:** the full Hyper-V role was *already* Disabled; only `VirtualMachinePlatform` (Enabled) + `hypervisorlaunchtype=Auto` keep the hypervisor up — i.e. **WSL2 is the sole reason the hypervisor runs**. Nothing to disable on the role side. Staged VBS/Credential Guard/HVCI off (effective next reboot). `hypervisorlaunchtype` + `VirtualMachinePlatform` left untouched.
- `[CLAUDE] 2026-05-20` — **VirtualBox 7.2.8r173730 installed** ✓, **Vagrant 2.4.9 installed** ✓ (msiexec 3010 = success/reboot-recommended). Both resolve on PATH (added VBox dir to USER PATH; `VBOX_MSI_INSTALL_PATH` set so Vagrant finds VBox).
- `[CLAUDE] 2026-05-20` — Boxes caching in background: `gusztavvargadr/windows-server-2022-standard` 2601.0.0 (downloading) and corrected Win10 box (see bug #2 below).

---

## ⚠️ [CLAUDE → CODEX] Two bugs found in `infrastructure/Vagrantfile` (your lane — not edited by me)

**Bug #1 — `vagrant validate` fails.** Line ~197:
```ruby
node.vm.provision "ansible", name: "ansible-site" do |ansible|
```
`vagrant validate` (Vagrant 2.4.9) rejects this: *"ansible remote provisioner: The following settings shouldn't exist: name"*. The `name:` keyword isn't a valid ansible-provisioner setting. Suggested fix:
```ruby
node.vm.provision "ansible-site", type: "ansible" do |ansible|
```
Everything else in the file validated cleanly once `AD_LAB_WINRM_PASSWORD` was set in the environment.

**Bug #2 — Win10 box name 404s.** Lines ~12-13:
```ruby
WIN10_BOX = "gusztavvargadr/windows-10-enterprise"   # <- does not exist (404)
WIN10_BOX_VERSION = "2511.0.0"
```
`gusztavvargadr/windows-10-enterprise` returns HTTP 404 from Vagrant Cloud. The correct box is **`gusztavvargadr/windows-10`** (gusztavvargadr's Windows 10 box ships the Enterprise eval edition). Version **`2511.0.0` is valid** for it (confirmed via the registry API). Suggested fix:
```ruby
WIN10_BOX = "gusztavvargadr/windows-10"
```
I pre-cached `gusztavvargadr/windows-10` 2511.0.0 so it's ready once you correct the name.

> Note: line ~61 of the Vagrantfile raises if `AD_LAB_WINRM_PASSWORD` is unset, so any `vagrant` command run from `infrastructure/` needs that env var (or run `vagrant box add` from another directory, which is what I did).

### Final progress
- `[CLAUDE] 2026-05-20` — Both boxes cached & checksum-verified: `gusztavvargadr/windows-server-2022-standard` 2601.0.0 and `gusztavvargadr/windows-10` 2511.0.0 (17.16 GB total; 345 GB free).
- `[CLAUDE] 2026-05-20` — Confirmed Vagrant works: a temp copy of the Vagrantfile **with bugs #1 and #2 fixed → `Vagrantfile validated successfully` (exit 0)**. So those two are the only blockers; the real file validates clean once Codex applies them. Codex's file was NOT modified.
- `[CLAUDE] 2026-05-20` — **Phase 0 host lane COMPLETE** (pending the user's reboot to apply staged VBS-off). See `PHASE0-CLAUDE-REPORT.md`. **Open user decision:** WSL2 (current) keeps VirtualBox in Hyper-V coexistence/"slow" mode; full native VBox speed for Phase 1 requires disabling `VirtualMachinePlatform` + `hypervisorlaunchtype off` (breaks Codex's WSL2). Recommend deciding before Phase 1 `vagrant up`.

### Final ready-state — `[CLAUDE] 2026-05-20`
- **DECISION: Option A confirmed by user** — keep WSL2 enabled, accept VirtualBox Hyper-V coexistence ("slow") mode. `VirtualMachinePlatform` stays **Enabled**. **No reboot** performed. (Staged VBS/Credential-Guard-off registry values remain; they're benign, don't affect WSL2, and will simply apply at the next natural reboot — no action required.)
- **Vagrantfile bugs #1 and #2 FIXED by Claude** (user authorized editing Codex's file):
  - line 13: `WIN10_BOX = "gusztavvargadr/windows-10"`
  - line 197: `node.vm.provision "ansible-site", type: "ansible" do |ansible|`
- **`vagrant validate` on the real `infrastructure/Vagrantfile` → `Vagrantfile validated successfully` (exit 0).** ✓
- Tools verified: VirtualBox `7.2.8r173730`, Vagrant `2.4.9`. Boxes cached: `windows-server-2022-standard` 2601.0.0, `windows-10` 2511.0.0 (17.16 GB). Both on PATH; `VBOX_MSI_INSTALL_PATH` set.

> ✅ **PHASE 1 IS READY TO START.** Host has VirtualBox 7.2.8 + Vagrant 2.4.9, both lab boxes pre-cached, and `infrastructure/Vagrantfile` validates clean (exit 0). To launch: from `infrastructure/`, set `AD_LAB_WINRM_PASSWORD` (and any vault args), then `vagrant up` per `docs/02-quick-start.md`. Expect coexistence-mode (slower) VM performance per Option A.
