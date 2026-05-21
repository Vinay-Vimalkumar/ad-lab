# 03 — Troubleshooting

> Phase-organized failure catalogue for the lab. Find your phase, scan the **Symptom** column, apply the **Fix**.

Related docs: [Environment Setup](00-environment-setup.md) · [Lab Architecture](01-lab-architecture.md) · [Quick Start](02-quick-start.md) · [Cleanup & Reset](04-cleanup-and-reset.md)

---

## Phase 1 — VirtualBox / Virtualization Host

| Symptom | Likely Cause | Fix |
|---------|--------------|-----|
| Green **turtle** icon on VM; guests run 5–20x slow | Hyper-V coexistence "slow" fallback active | Disable Hyper-V hypervisor: `bcdedit /set hypervisorlaunchtype off`; turn off Memory Integrity / Credential Guard ([Setup §1](00-environment-setup.md#1-disable-hyper-v-and-the-virtualization-security-stack)); reboot. |
| `VERR_VMX_NO_VMX` / "VT-x is not available" | VT-x disabled in firmware or owned by Windows hypervisor | Enable Intel VT-x + VT-d in UEFI; verify `systeminfo` → *Virtualization Enabled In Firmware: Yes*; ensure `hypervisorlaunchtype Off`. |
| `VBoxManage hostonlyif` / VBoxNetAdpCtl: *Error while adding new interface* | Networking driver state / restricted range | Repair-install VirtualBox (re-run installer → Repair), reboot; recreate adapter with `VBoxManage hostonlyif create`. |
| `Nonexistent host networking interface, name 'vboxnet0'` on `vagrant up` | Host-only network / subnet not allowlisted | Add `* 192.168.56.0/21` to `C:\ProgramData\VirtualBox\networks.conf`; recreate the host-only adapter. |
| Extension Pack features (RDP, USB2/3) unavailable | Extension Pack not installed or version-mismatched | `VBoxManage list extpacks`; install the **matching** version Extension Pack. |

## Phase 2 — Vagrant

| Symptom | Likely Cause | Fix |
|---------|--------------|-----|
| `vagrant up` hangs on **"Waiting for domain"** / WinRM never connects | Guest mid-DCPROMO reboot, WinRM listener not yet up, or DNS not resolving the new domain | Wait one reboot cycle (DCs reboot during promotion); if still stuck >20 min, `vagrant reload <vm>`; confirm WinRM (Phase 3). |
| `The box ... could not be found` | Base box not added / wrong name in Vagrantfile | `vagrant box list`; let `vagrant up` re-download or `vagrant box add` the WS2022/Win10 box. |
| Guest Additions / shared folder errors after kernel/box update | vbguest mismatch | `vagrant vbguest --do install <vm>`; ensure `vagrant-vbguest` plugin installed. |
| `vagrant up` fails immediately with VT-x/Hyper-V error | Host still running Hyper-V hypervisor | Return to [Setup §1](00-environment-setup.md#1-disable-hyper-v-and-the-virtualization-security-stack); set `hypervisorlaunchtype off`; reboot. |
| Members provision before DCs exist (join fails) | Wrong boot order | Bring up `kingslanding` then `winterfell` first, then members ([Quick Start §3](02-quick-start.md)). |

## Phase 3 — Ansible / WinRM

| Symptom | Likely Cause | Fix |
|---------|--------------|-----|
| `ssl: HTTPSConnectionPool ... certificate verify failed` | WinRM cert validation on self-signed listener | Set `ansible_winrm_server_cert_validation=ignore`. |
| `the specified credentials were rejected by the server` (HTTP 401) | Wrong transport / domain creds / NTLM vs Kerberos | Use `ansible_winrm_transport=ntlm`, full `DOMAIN\user` or UPN, correct `{{LAB_PASSWORD}}`. |
| `Read timed out` / `Operation timed out` mid-play | WinRM `MaxMemoryPerShellMB` / long reboot / firewall | Raise WinRM quotas on guest; add `ansible_winrm_operation_timeout_sec`/`read_timeout_sec`; allow WinRM (5985/5986) through guest firewall. |
| `winrm or requests is not installed` on control node | `pywinrm` missing | `pip install --user pywinrm` in the control node ([Setup §5c](00-environment-setup.md#5c-required-collections--winrm-dependency)). |
| Control node (WSL) cannot reach `192.168.56.x` | WSL2 NAT isolation from host-only net | Run Ansible from the Windows host, or set `networkingMode=mirrored` in `.wslconfig` then `wsl --shutdown` ([Setup §4b](00-environment-setup.md#4b-wslconfig-host-side-userprofilewslconfig)). |

## Phase 4 — Windows Domain Join / AD

| Symptom | Likely Cause | Fix |
|---------|--------------|-----|
| Member join fails: *"domain could not be contacted"* | Client DNS points at router/`8.8.8.8` instead of the DC | Set the member's primary DNS to its DC (`.10` for sevenkingdoms, `.12` for north); `ipconfig /flushdns`; retry join. |
| Cross-domain resolution fails (`north.*` can't find root) | Missing delegation / conditional forwarder | On `winterfell`, ensure conditional forwarder to `sevenkingdoms.local` → `192.168.56.10`; `nltest /dsgetdc:sevenkingdoms.local`. |
| `Get-ADTrust` shows no trust / child won't promote | Child promoted before root was reachable | Verify root DC online + DNS; re-run child promotion; check `repadmin /replsummary`. |
| Logons fail with **KRB_AP_ERR_SKEW** / *clock skew too great* | Time drift between guests > 5 min (Kerberos tolerance) | Sync time to the PDC emulator: on members `w32tm /resync`; configure `kingslanding` (PDCe) as authoritative time source; ensure VBox guest time-sync isn't fighting it. |
| `nltest /sc_query` shows broken secure channel | Snapshot restore desynced the machine password | `Test-ComputerSecureChannel -Repair -Credential <DA>`, or rejoin; prefer restoring **all** VMs to the same snapshot set ([Cleanup §reset](04-cleanup-and-reset.md)). |

## Phase 5 — Attack Tooling

| Symptom | Likely Cause | Fix |
|---------|--------------|-----|
| Impacket `KRB_AP_ERR_SKEW (Clock skew too great)` | Attacker host clock differs from DC | Sync attacker to DC time: `ntpdate 192.168.56.10` / `sudo timedatectl set-ntp` then match DC; or use `faketime`. |
| Rubeus / Kerberos requests fail with `KDC_ERR_PREAUTH_FAILED` | Wrong password/hash, or account requires pre-auth | Verify credential; for AS-REP roast confirm target has *Do not require Kerberos preauth* set. |
| `crackmapexec smb` shows hosts but all auth fails | Wrong domain or NetBIOS, SMB signing required | Use correct `-d sevenkingdoms.local` / `north.sevenkingdoms.local`; supply DA creds; note signing required on DCs. |
| BloodHound CE ingest shows no sessions/edges | Collected from unprivileged context or wrong collector | Run SharpHound/`bloodhound-python` with valid domain creds against the right `{{DC_IP}}`; collect both domains. |
| Mimikatz `ERROR kuhl_m_sekurlsa_acquireLSA` | LSASS protection / wrong privilege / Defender | Run elevated + `privilege::debug`; in this lab disable RunAsPPL/Defender on the target for the exercise (lab-only). |

---

## Quick Diagnostic Cheatsheet

```powershell
# Trust + replication health (run on a DC)
Get-ADTrust -Filter *
repadmin /replsummary
nltest /dsgetdc:north.sevenkingdoms.local

# Time / Kerberos skew
w32tm /query /status
w32tm /resync

# DNS sanity from a member
Resolve-DnsName sevenkingdoms.local
nltest /sc_query:sevenkingdoms.local
```

```bash
# WinRM reachability from the control node
ansible -i 192.168.56.10, all -m win_ping \
  -e ansible_connection=winrm -e ansible_winrm_transport=ntlm \
  -e ansible_user=Administrator -e ansible_password='{{LAB_PASSWORD}}' \
  -e ansible_winrm_server_cert_validation=ignore
```

---
Last updated: 2026-05-17
References: https://attack.mitre.org/ · https://attack.mitre.org/techniques/T1558/ (Steal/Forge Kerberos Tickets) · https://attack.mitre.org/techniques/T1078/002/ (Domain Accounts)
