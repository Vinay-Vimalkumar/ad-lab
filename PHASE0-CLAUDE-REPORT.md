# Phase 0 — Windows Host Lane Report (Claude)

**Date:** 2026-05-20 · **Host:** Windows 11 Pro N · i9-12900F · 32 GB RAM · 345 GB free (post-box-cache)
**Lane:** Windows host — Hyper-V/VBS, VirtualBox, Vagrant, PATH, box cache, Vagrantfile validation.
**Counterpart:** Codex (WSL2 + Ubuntu 22.04 + Ansible) — separate lane, coordinated via [`PHASE0-STATUS.md`](PHASE0-STATUS.md).

---

## Outcome: ✅ Host lane complete (one user action pending: a coordinated reboot)

| # | Deliverable | Status | Evidence |
|---|-------------|--------|----------|
| 1 | Check + document Hyper-V state | ✅ | See "Hyper-V findings" below |
| 2 | Disable Hyper-V (DISM / Windows Features) | ✅ (already off) + VBS staged off | Full Hyper-V role was already `Disabled`; staged VBS/Cred Guard/HVCI off |
| 3 | Handle reboot requirement | ✅ documented | No forced reboot (Codex live in WSL2); reboot deferred to user — see below |
| 4 | Download VirtualBox 7.x + SHA256 verify | ✅ | 7.2.8 build 173730; hash `ae5415cc…1606` matched published SHA256SUMS |
| 5 | Install VirtualBox silently | ✅ | `--silent --msiparams REBOOT=ReallySuppress`, installer exit 0 |
| 6 | Verify VirtualBox | ✅ | `VBoxManage --version` → `7.2.8r173730` |
| 7 | Download Vagrant + SHA256 verify | ✅ | 2.4.9; MSI hash `3bdd9679…cbe3` matched published SHA256SUMS |
| 8 | Install Vagrant silently | ✅ | `msiexec /i … /qn /norestart`, exit `3010` (success, reboot-recommended) |
| 9 | Verify Vagrant | ✅ | `vagrant --version` → `Vagrant 2.4.9` |
| 10 | Add VirtualBox + Vagrant to PATH | ✅ | Vagrant on machine PATH (installer); VBox dir added to USER PATH; both resolve by name |
| 11 | Pre-download the two boxes | ✅ (1 corrected) | `windows-server-2022-standard` 2601.0.0 ✓; **`windows-10` 2511.0.0** ✓ (Vagrantfile name was wrong — see bugs) |
| 12 | `vagrant validate` passes | ⚠️ blocked by Vagrantfile bug | Vagrant works; a fixed **copy** validated clean (exit 0). Real file needs Codex's 2 fixes |
| 13 | This report | ✅ | — |

---

## Hyper-V findings (important)

The elevated state dump revealed the host was **not** in the expected "Hyper-V fully on" state:

```
Microsoft-Hyper-V-All           Disabled     <- full role already off
Microsoft-Hyper-V               Disabled
VirtualMachinePlatform          Enabled      <- this is what runs the hypervisor (for WSL2)
HypervisorPlatform              Disabled
Containers-DisposableClientVM   Disabled
hypervisorlaunchtype            Auto
```

So `systeminfo`'s "A hypervisor has been detected" comes **solely from `VirtualMachinePlatform` + `hypervisorlaunchtype=Auto`**, which exist to run **Codex's WSL2**. The heavyweight Hyper-V role was already disabled — there was nothing to turn off there.

**What I changed (elevated, reversible, effective next reboot):**
- Staged VBS off: HVCI/Memory Integrity, Credential Guard, Device Guard, LsaCfgFlags = 0.
- Left `VirtualMachinePlatform`, `HypervisorPlatform`, and `hypervisorlaunchtype` **untouched** to avoid breaking WSL2.

---

## ⚠️ Open decision for the user — VirtualBox speed vs. WSL2

This is the core tension from [`docs/00-environment-setup.md`](docs/00-environment-setup.md) §0, now concrete:

- **Current state (WSL2 preserved):** the hypervisor runs at boot → VirtualBox 7.x runs in **Hyper-V coexistence ("slow"/turtle) mode**. Functional for building and validating the lab, but nested-DC AD replication will be noticeably slower.
- **Full native VirtualBox speed** requires `VirtualMachinePlatform` **disabled** *and* `bcdedit /set hypervisorlaunchtype off` — which **breaks Codex's WSL2** (where Ansible lives).

I did **not** make this call unilaterally because it would disrupt a teammate's actively-used environment. **Options before Phase 1 `vagrant up`:**

| Option | VBox speed | WSL2/Ansible | Action |
|--------|-----------|--------------|--------|
| **A. Keep WSL2 (current)** | Coexistence (slower) | Works on host | Nothing; just reboot to apply VBS-off |
| **B. Native VBox speed** | Full native VT-x | Must move Ansible off host WSL2 (use a Linux guest, or run Ansible from the host) | Disable `VirtualMachinePlatform`, `hypervisorlaunchtype off`, reboot |

My recommendation: for a 5-VM AD lab with nested DCs, **Option B** gives a much better experience, but only adopt it once Codex's Ansible workflow is relocated off WSL2. Until then, **Option A** is fine for provisioning and validation.

---

## Reboot requirement

A reboot is needed to apply the staged VBS/Credential Guard disable (and to finalize Vagrant's PATH for brand-new shells). **I did not force it** — Codex was actively working inside WSL2 and a reboot would kill that session.

- I did **not** create a RunOnce/scheduled-task auto-resume, because nothing in my remaining work needed post-reboot continuation (all deliverables completed pre-reboot). Adding an auto-run elevated task would also be an unnecessary persistence footprint.
- **User action:** when you and Codex are at a safe stopping point, reboot once. After reboot, re-open a terminal so `vagrant`/`VBoxManage` are on PATH everywhere. If you choose Option B above, apply those changes in the same elevated session before rebooting.

---

## 🐞 Two bugs found in Codex's `infrastructure/Vagrantfile` (not edited by me — flagged in PHASE0-STATUS.md)

**Bug #1 — `vagrant validate` rejects an invalid ansible-provisioner setting (line ~197):**
```ruby
# current (fails: "ansible remote provisioner: The following settings shouldn't exist: name")
node.vm.provision "ansible", name: "ansible-site" do |ansible|
# fix
node.vm.provision "ansible-site", type: "ansible" do |ansible|
```

**Bug #2 — Win10 box name 404s (lines ~12-13):**
```ruby
# current (HTTP 404 from Vagrant Cloud)
WIN10_BOX = "gusztavvargadr/windows-10-enterprise"
# fix (this box ships the Win10 Enterprise eval edition; version 2511.0.0 is valid)
WIN10_BOX = "gusztavvargadr/windows-10"
```

With both fixes applied to a throwaway copy, `vagrant validate` returned **`Vagrantfile validated successfully` (exit 0)** — so these are the only two blockers. I pre-cached `gusztavvargadr/windows-10` 2511.0.0 so it's ready the moment Codex corrects the name.

---

## Current installed state (verified)

| Component | Version / Value |
|-----------|-----------------|
| VirtualBox | `7.2.8r173730` (`C:\Program Files\Oracle\VirtualBox\`) |
| Vagrant | `2.4.9` (`C:\Program Files\Vagrant\bin\`) |
| `VBOX_MSI_INSTALL_PATH` | `C:\Program Files\Oracle\VirtualBox\` (so Vagrant locates VBox) |
| Cached boxes | `windows-server-2022-standard` 2601.0.0; `windows-10` 2511.0.0 (17.16 GB) |
| Extension Pack | **Not installed** (not required for the lab; can add later with `VBoxManage extpack install --accept-license`) |
| Disk free (C:) | 345 GB |

---

## Errors / friction encountered

1. **UAC elevation canceled twice** before being approved on the third attempt. All admin work (feature changes + installs) was bundled into one elevated script (`%TEMP%\phase0-claude-elevated.ps1`, log `%TEMP%\phase0-claude-elevated.log`) to minimize prompts.
2. **`vagrant box add` initially failed at Vagrantfile line 61** because it ran from `infrastructure/` (Vagrant auto-loads the local Vagrantfile, which requires `AD_LAB_WINRM_PASSWORD`). Fixed by running `box add` from a Vagrantfile-free directory (box add is global).
3. **Win10 box 404** — wrong box name in the Vagrantfile (bug #2). Resolved by identifying the correct `gusztavvargadr/windows-10`.

---

## Next steps (Phase 1 readiness)

1. **Codex:** apply Vagrantfile bugs #1 and #2.
2. **User:** decide Option A vs B (VBox speed vs WSL2), then reboot once at a coordinated time.
3. After reboot: from `infrastructure/`, set `AD_LAB_WINRM_PASSWORD` (and any vault args), run `vagrant validate` (should pass), then `vagrant up` per [`docs/02-quick-start.md`](docs/02-quick-start.md).
4. Boxes are pre-cached, so `vagrant up` will skip the ~17 GB download.

---

Last updated: 2026-05-20
References: [`docs/00-environment-setup.md`](docs/00-environment-setup.md) · [`PHASE0-STATUS.md`](PHASE0-STATUS.md) · https://www.virtualbox.org/ · https://developer.hashicorp.com/vagrant
