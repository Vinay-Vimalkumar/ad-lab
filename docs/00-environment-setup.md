# 00 — Host Environment Setup (Windows 11 Pro N Preflight)

> **Audience:** The lab operator preparing the physical host before any VM is built.
> **Host spec:** Windows 11 Pro N · Intel i9-12900F (16C/24T) · 32 GB RAM · 367 GB free.
> **Goal:** A clean Type-2 hypervisor (VirtualBox 7.x) running at full hardware-virtualization speed, plus a WSL2 Ubuntu 22.04 control node for Ansible.

Related docs: [Lab Architecture](01-lab-architecture.md) · [Quick Start](02-quick-start.md) · [Troubleshooting](03-troubleshooting.md) · [Cleanup & Reset](04-cleanup-and-reset.md)

---

## 0. The Core Tension (Read This First)

VirtualBox 7.x and the Windows virtualization stack fight over the CPU's VT-x extensions.

- **VirtualBox wants raw VT-x.** When any Hyper-V component is active, Windows owns the root partition and VirtualBox is forced into a **Hyper-V coexistence ("slow") fallback**. You will see the green turtle icon in the VM status bar and 5–20x slower guest performance. Nested DCs replicating AD will crawl.
- **WSL2 needs `VirtualMachinePlatform`**, which is a Hyper-V-adjacent component. So a *pure* "all Hyper-V off" host cannot run WSL2.

**Recommended clean path for this lab (chosen approach):**

1. Disable the heavyweight Hyper-V hypervisor and the security features that silently re-enable it (Memory Integrity / Credential Guard / Device Guard).
2. **Keep `VirtualMachinePlatform` enabled only if you need WSL2 on the same host.** With `hypervisorlaunchtype off`, VirtualBox 7.x runs natively *as long as the Hyper-V hypervisor itself is not launched at boot*. `VirtualMachinePlatform` alone (without `Microsoft-Hyper-V` / Credential Guard) generally does **not** force VirtualBox into slow mode on VirtualBox 7.x.
3. If you observe the turtle/slow icon even after this, **move the Ansible control node off WSL2** (use a small Ubuntu VirtualBox guest or run Ansible from a Linux box) and disable `VirtualMachinePlatform` entirely. That is the only guaranteed conflict-free configuration.

> **KNOWN TENSION (logged):** WSL2 (`VirtualMachinePlatform`) vs. VirtualBox native VT-x. On VirtualBox 7.x they usually coexist with `hypervisorlaunchtype off`; if performance regresses, drop WSL2 and run Ansible from a guest VM. Re-validate after every Windows feature update — updates love to re-arm Core Isolation.

---

## 1. Disable Hyper-V and the Virtualization Security Stack

Run **all** commands in an **elevated** PowerShell (Run as Administrator). Reboot when prompted; several changes only take effect at the next boot.

### 1a. Disable the Hyper-V feature (DISM, both syntaxes)

```powershell
# Classic DISM feature disable (note: no space after the colon form)
DISM /Online /Disable-Feature:Microsoft-Hyper-V

# PowerShell DISM cmdlet — disables the umbrella "All" feature + sub-features
Disable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -NoRestart
```

Expected output (cmdlet form):

```text
Path          :
Online        : True
RestartNeeded : True
```

### 1b. Disable companion virtualization features

```powershell
# Windows Hypervisor Platform (3rd-party hypervisor API surface)
Disable-WindowsOptionalFeature -Online -FeatureName HypervisorPlatform -NoRestart

# Windows Sandbox (silently pulls in the Hyper-V hypervisor)
Disable-WindowsOptionalFeature -Online -FeatureName Containers-DisposableClientVM -NoRestart

# Virtual Machine Platform — DISABLE ONLY IF YOU ARE NOT USING WSL2.
# Leave ENABLED if you want WSL2 on this host (see section 0).
# Disable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -NoRestart
```

### 1c. Turn off the boot-time hypervisor launch

```powershell
bcdedit /set hypervisorlaunchtype off
```

Expected:

```text
The operation completed successfully.
```

Verify:

```powershell
bcdedit /enum | Select-String hypervisorlaunchtype
# hypervisorlaunchtype    Off
```

### 1d. Disable Memory Integrity / Core Isolation (HVCI)

Core Isolation > Memory Integrity is the #1 cause of "Hyper-V re-enabling itself." Disable via registry, then reboot:

```powershell
$p = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity'
New-Item -Path $p -Force | Out-Null
Set-ItemProperty -Path $p -Name 'Enabled' -Value 0 -Type DWord
```

### 1e. Disable Credential Guard and Device Guard

```powershell
$dg = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard'
New-Item -Path $dg -Force | Out-Null
Set-ItemProperty -Path $dg -Name 'EnableVirtualizationBasedSecurity' -Value 0 -Type DWord
Set-ItemProperty -Path $dg -Name 'RequirePlatformSecurityFeatures' -Value 0 -Type DWord

$lsa = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'
Set-ItemProperty -Path $lsa -Name 'LsaCfgFlags' -Value 0 -Type DWord
```

> If Credential Guard was ever enabled with UEFI lock, you may also need to clear it via the Microsoft "Device Guard and Credential Guard hardware readiness" tool and re-flash the UEFI variable. Most fresh Win11 Pro N installs do not lock it.

**Reboot now.** Into UEFI if needed (next section), otherwise back into Windows.

### 1f. Post-reboot verification

```powershell
# Hyper-V services should be Stopped/Disabled
Get-Service vmms,hvhost,vmcompute | Format-Table Name,Status,StartType -Auto

# msinfo32 acid test — look for the VBS line
systeminfo | Select-String "Hyper-V","Virtualization"
```

Expected (success state for native VirtualBox):

```text
Status   Name        StartType
------   ----        ---------
Stopped  vmms        Disabled
Stopped  hvhost      Disabled

Virtualization-based security: Not enabled
A hypervisor has been detected. Features required for Hyper-V will not be displayed.   <-- you do NOT want this line
```

If `systeminfo` still says *"A hypervisor has been detected,"* something re-armed it — go to [Troubleshooting](#7-troubleshooting).

---

## 2. Install VirtualBox 7.x (with SHA256 verification)

1. Download the Windows host installer and the matching `SHA256SUMS` file from <https://www.virtualbox.org/wiki/Downloads>.
2. Verify integrity before running the installer:

```powershell
cd "$env:USERPROFILE\Downloads"
Get-FileHash -Algorithm SHA256 .\VirtualBox-7.*-Win.exe

# Compare against the published checksum
Get-Content .\SHA256SUMS | Select-String "Win.exe"
```

Expected (hashes must match exactly, case-insensitive):

```text
Algorithm  Hash                                                              Path
---------  ----                                                              ----
SHA256     9F3C...A1B2...redacted...0E4D                                     ...\VirtualBox-7.x-Win.exe
```

3. Install silently or via GUI:

```powershell
Start-Process .\VirtualBox-7.*-Win.exe -ArgumentList '--silent' -Wait
```

4. Install the matching **Extension Pack** (download separately, same version) and verify:

```powershell
& "$env:ProgramFiles\Oracle\VirtualBox\VBoxManage.exe" --version
# 7.x.xr<build>

& "$env:ProgramFiles\Oracle\VirtualBox\VBoxManage.exe" list extpacks
# Pack no. 0:   Oracle VM VirtualBox Extension Pack ... Usable: true
```

---

## 3. Install Vagrant + vbguest plugin

1. Install Vagrant (latest) from <https://developer.hashicorp.com/vagrant/downloads> or via winget:

```powershell
winget install --id Hashicorp.Vagrant -e
```

2. Open a **new** terminal (PATH refresh) and verify:

```powershell
vagrant --version
# Vagrant 2.x.x
```

3. Install the guest-additions auto-sync plugin:

```powershell
vagrant plugin install vagrant-vbguest
vagrant plugin list
# vagrant-vbguest (0.x.x, global)
```

> The Vagrantfile and Ansible provisioners live in [`/infrastructure/`](../infrastructure/) (owned by a teammate). Do not edit them from here.

---

## 4. Install WSL2 + Ubuntu 22.04

> Only if you are running the Ansible control node on the host (see section 0 tension).

```powershell
wsl --install -d Ubuntu-22.04
```

Expected:

```text
Installing: Windows Subsystem for Linux
Installing: Ubuntu 22.04 LTS
The requested operation is successful. Changes will not be effective until the system is rebooted.
```

After reboot, set WSL default to v2 and verify:

```powershell
wsl --set-default-version 2
wsl --list --verbose
#   NAME            STATE           VERSION
# * Ubuntu-22.04    Running         2
```

### 4a. `/etc/wsl.conf` (inside the distro)

```ini
# /etc/wsl.conf
[boot]
systemd=true

[network]
generateResolvConf=true

[interop]
appendWindowsPath=false
```

### 4b. `.wslconfig` (host side, `%UserProfile%\.wslconfig`)

```ini
# C:\Users\vinay\.wslconfig
[wsl2]
memory=8GB          # cap WSL2 RAM so the 5 VMs keep their budget
processors=4
swap=2GB
networkingMode=NAT  # use 'mirrored' only if NAT can't reach 192.168.56.0/24
localhostForwarding=true
```

Apply changes:

```powershell
wsl --shutdown   # then reopen the distro
```

---

## 5. Install Ansible inside WSL (apt and pipx)

### 5a. Option A — distro package (apt)

```bash
sudo apt update && sudo apt install -y software-properties-common
sudo add-apt-repository --yes --update ppa:ansible/ansible
sudo apt install -y ansible
ansible --version
# ansible [core 2.1x.x]
```

### 5b. Option B — isolated install (pipx, recommended for pinning)

```bash
sudo apt install -y pipx python3-pip
pipx ensurepath
pipx install --include-deps ansible
exec $SHELL -l
ansible --version
```

### 5c. Required collections + WinRM dependency

Windows targets need `pywinrm` and the Windows-focused collections:

```bash
pip install --user pywinrm
ansible-galaxy collection install ansible.windows
ansible-galaxy collection install community.windows
ansible-galaxy collection install microsoft.ad
ansible-galaxy collection list | grep -E "ansible.windows|community.windows|microsoft.ad"
```

Expected:

```text
ansible.windows     2.x.x
community.windows   2.x.x
microsoft.ad        1.x.x
```

Quick connectivity sanity check (after VMs are up — see [Quick Start](02-quick-start.md)):

```bash
ansible -i 192.168.56.10, all -m win_ping \
  -e ansible_user=Administrator -e ansible_password='{{LAB_PASSWORD}}' \
  -e ansible_connection=winrm -e ansible_winrm_transport=ntlm \
  -e ansible_winrm_server_cert_validation=ignore
# 192.168.56.10 | SUCCESS => { "changed": false, "ping": "pong" }
```

---

## 6. Tool Version Matrix (for reference)

| Tool | Version | Where it runs |
|------|---------|---------------|
| VirtualBox | 7.x | Host |
| Vagrant | latest | Host |
| Ansible | core 2.1x | WSL2 / control node |
| Impacket | v0.12.0 | Attacker (WSL/Kali) |
| Rubeus | v2.3.2 | Windows guest |
| BloodHound CE | 6.x | Host/attacker |
| Sysmon | v15.x | Windows guests (detection) |
| Mimikatz | 2.2.0 | Windows guest |
| hashcat | v6.2.6 | Host (GPU) |

---

## 7. Troubleshooting

### VT-x not available / "VERR_VMX_NO_VMX"
- **BIOS/UEFI:** Reboot into firmware (Win11: *Settings > System > Recovery > Advanced startup > UEFI Firmware Settings*). Enable **Intel Virtualization Technology (VT-x)** and **VT-d**. On i9-12900F these live under *Advanced > CPU Configuration*. Save and exit.
- After enabling in firmware, confirm in Windows: `systeminfo | Select-String "Virtualization Enabled In Firmware"` should read `Yes`.

### Hyper-V keeps re-enabling itself
- **Memory Integrity / Core Isolation** re-arms after Windows Updates. Re-run section **1d** and reboot. Check *Settings > Privacy & security > Windows Security > Device Security > Core isolation* — Memory Integrity must be **Off**.
- **Windows Sandbox / WSL2** silently require Hyper-V components. If you see the slow turtle in VirtualBox, decide between WSL2 and native speed (section 0).
- **WSL2 dependency note:** `wsl --install` re-enables `VirtualMachinePlatform`. That is expected and usually fine on VBox 7.x; only `Microsoft-Hyper-V`/`hypervisorlaunchtype on` forces slow mode.
- Verify the hypervisor is truly off: `bcdedit /enum | Select-String hypervisorlaunchtype` → `Off`.

### WSL networking can't reach the host-only subnet
- Default **NAT** mode isolates WSL2 from the `192.168.56.0/24` host-only network. Either:
  - Run Ansible against VMs by their host-only IPs from the **Windows host** (not WSL), or
  - Switch `.wslconfig` to `networkingMode=mirrored` (Win11 22H2+), then `wsl --shutdown`. Mirrored mode shares the host's interfaces and can reach host-only adapters.
- Test from WSL: `ping 192.168.56.10`. If it fails under NAT, mirrored mode or a host-side control node is required.

### VBoxNetAdpCtl / host-only adapter errors
- VirtualBox 7.x restricts host-only ranges. Allowlist the lab subnet:

```text
# C:\ProgramData\VirtualBox\networks.conf   (Windows path of /etc/vbox/networks.conf)
* 192.168.56.0/21
* fe80::/64
```

- Recreate the adapter if missing:

```powershell
& "$env:ProgramFiles\Oracle\VirtualBox\VBoxManage.exe" hostonlyif create
& "$env:ProgramFiles\Oracle\VirtualBox\VBoxManage.exe" list hostonlyifs
```

- If you get `VBoxNetAdpCtl: Error while adding new interface`, reinstall VirtualBox networking drivers (re-run the installer > Repair) and reboot.

More phase-by-phase fixes live in [Troubleshooting](03-troubleshooting.md).

---
Last updated: 2026-05-17
References: https://attack.mitre.org/ · https://attack.mitre.org/matrices/enterprise/windows/ · https://attack.mitre.org/tactics/TA0005/
