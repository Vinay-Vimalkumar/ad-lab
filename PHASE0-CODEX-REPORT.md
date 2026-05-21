# Phase 0 Codex Report

## Scope

Codex handled the WSL2, Ubuntu, Ansible, Ansible collections, and WinRM Python dependency side of Phase 0. Claude owns Hyper-V policy, VirtualBox, and Vagrant.

## Current WSL State

- `wsl --status` reports default distribution `Ubuntu` and default version `2`.
- `wsl --list --verbose` reports:
  - `Ubuntu` stopped/runnable, WSL version `2`
  - `kali-linux` stopped/runnable, WSL version `2`
- `wsl --version` reports WSL `2.7.3.0` and kernel `6.6.114.1-1`.
- Existing default `Ubuntu` distro is Ubuntu `22.04.3 LTS`.
- Default Ubuntu user is `vinay`.
- No first-launch user setup was needed; no temporary password was created or stored.
- Windows optional feature inspection from this non-elevated shell requires admin/UAC, but WSL2 is operational, so the required WSL/VMP plumbing is functionally present.

## Work Completed

- Read `docs/00-environment-setup.md`.
- Created and maintained `PHASE0-STATUS.md` because it was missing at Codex start.
- Ran `apt-get update`.
- Ran `apt-get upgrade -y`.
- Installed/confirmed `software-properties-common` and `python3-pip`.
- Added the Ansible PPA: `ppa:ansible/ansible`.
- Installed Ubuntu packages:
  - `ansible`
  - `ansible-core`
  - `python3-winrm` and supporting WinRM packages pulled by apt
- Installed/upgraded user-local `pywinrm` with pip:
  - `pywinrm 0.5.0`
- Installed/confirmed Ansible collections:
  - `ansible.windows 3.5.0`
  - `community.windows 3.1.0`
  - `microsoft.ad 1.10.0`
- Ran `wsl --set-default-version 2`; it completed successfully.
- Ran the lab playbook syntax check from inside WSL:
  - `ansible-playbook --syntax-check -i inventory.yml site.yml -e vault_lab_password='Password123!'`
  - Result: passed.
- Installed CredSSP support for Ansible WinRM:
  - `requests-credssp 2.0.0`
  - `pyspnego 0.12.1`
- Added `infrastructure/provisioning/ansible/preflight-connectivity.yml`.
- Restored `infrastructure/provisioning/ansible/group_vars/all/main.yml` because Ansible was not loading the top-level `group_vars/all.yml` while the `group_vars/all/` directory existed.
- Ran inventory-only preflight in check mode; all five hosts resolved with the expected WinRM/CredSSP metadata.
- Ran an expected-fail WinRM auth probe against the five future VM IPs. It reached the CredSSP WinRM connection code path and failed with `No route to host`, which is expected before `vagrant up`.

## Networking Verification

- WSL Ubuntu interface: `eth0` on `172.25.193.30/20`.
- Default route: `172.25.192.1`.
- Verified outbound IP connectivity with `ping -c 2 8.8.8.8`.
- Verified DNS resolution with `getent hosts archive.ubuntu.com`.
- The VirtualBox host-only subnet `192.168.56.0/24` is not expected to be reachable until Claude's VirtualBox/Vagrant lane creates the host-only adapter and VMs.

## Notes and Errors

- `Get-WindowsOptionalFeature` requires elevation from this shell, so direct feature-state output was not captured. WSL2 itself runs successfully.
- `wsl --update --status` is not supported by this installed WSL CLI and returned `E_INVALIDARG`; `wsl --version` was used to verify the installed WSL/kernel version instead.
- Apt kept back these Ubuntu packages during `apt-get upgrade -y`:
  - `libnetplan0`
  - `netplan.io`
  - `ubuntu-advantage-tools`
  - `ubuntu-pro-client-l10n`
  - `ubuntu-wsl`
  - `wsl-setup`
- Both apt-installed Ansible and user-local pip Ansible are present. The normal `vinay` shell resolves `ansible` to `/home/vinay/.local/bin/ansible`, version `core 2.17.14`; `/usr/bin/ansible` is also installed and reports the same core version.

## Current State

- WSL2/Ubuntu/Ansible lane is ready for provisioning syntax validation and future WinRM connectivity once Vagrant VMs are up.
- No Windows reboot was triggered by Codex.
- No duplicate `Ubuntu-22.04` distro was installed because the existing `Ubuntu` distro already satisfies Ubuntu 22.04 LTS.
- As requested after Phase 0 completion, Codex did not edit `infrastructure/Vagrantfile`; Claude owns the two known fixes there.
- `ansible-lint site.yml preflight-connectivity.yml` passes at the production profile.

## Next Steps

- Both lanes are idle until the user starts Phase 1 with `vagrant up`.
- After Vagrant creates the `192.168.56.0/24` host-only network and VMs, run:
  - `cd /mnt/c/Users/vinay/Downloads/ad-lab/infrastructure/provisioning/ansible`
  - `ANSIBLE_CONFIG=./ansible.cfg ansible-playbook -i inventory.yml preflight-connectivity.yml -e vault_lab_password='Password123!'`
- If WSL NAT cannot reach the host-only adapter, use the troubleshooting path in `docs/00-environment-setup.md`: switch WSL networking to mirrored mode or run Ansible from a host/guest that can route to `192.168.56.0/24`.
