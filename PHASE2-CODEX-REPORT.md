# Phase 2 Codex Report

Generated: `2026-05-21T00:22:00-04:00`

## Summary

Phase 2 completed from the `ansible-control` Linux VM. The lab now has two AD domains, all three member/workstation systems joined, identity objects and vulnerable attack paths provisioned, and Sysmon deployed on all five Windows VMs.

Ready for attacks: yes.

## Role Outcomes

- `common`: completed earlier on all five VMs.
- `forest_root`: completed on `kingslanding`; `sevenkingdoms.local` exists.
- `child_domain`: recovered and completed on `winterfell`; `north.sevenkingdoms.local` exists with parent-child trust.
- `domain_join`: completed on `castelblack`, `meereen`, and `braavos`; all rebooted and joined expected domains.
- `users_and_ous`: completed on both DCs.
- `service_accounts`: completed on both DCs.
- `asrep_accounts`: completed on both DCs.
- `delegation_accounts`: completed on both DCs.
- `vulnerable_gpos`: completed on both DCs.
- `acl_misconfigurations`: completed on `kingslanding`.
- `sysmon_deployment`: completed on all five VMs.

## Verification Results

- Domain membership:
  - `KINGSLANDING`, `CASTELBLACK`, and `BRAAVOS` are in `sevenkingdoms.local`.
  - `WINTERFELL` and `MEEREEN` are in `north.sevenkingdoms.local`.
- Trust:
  - `nltest /domain_trusts` shows direct inbound/outbound within-forest trust between `SEVENKINGDOMS` and `NORTH`.
- Users:
  - Root domain user count: `35`.
  - Child domain user count: `16`.
- SPNs:
  - Root: `svc_mssql`, `svc_web`, `svc_cifs`.
  - Child: `svc_ldap`.
- UAC flags:
  - `jon.snow`, `arya.stark`, `sansa.stark`: `DONT_REQ_PREAUTH=True`.
  - `cersei.lannister`, `brandon.stark`: `TrustedForDelegation=True`.
- GPOs:
  - Root domain GPO count: `5`.
  - Child domain GPO count: `5`.
- Sysmon:
  - `Sysmon64` is `Running` and `Automatic` on all five hosts.
  - Sysmon Event ID `1` baseline process-creation events were observed on all five hosts.

## Retries And Debugging

- Killed stale `ansible-playbook` PIDs `5382` and `5393` after the original child-domain promotion left a zombie WinRM socket.
- Added bounded WinRM timeouts: operation `600s`, read `900s`.
- Recovered `winterfell` child-domain promotion after DCPROMO completed but Ansible lost the reboot handoff.
- Cleaned DC DNS registration so DC locator uses the host-only `192.168.56.x` addresses instead of VirtualBox NAT or IPv6 records.
- Switched post-promotion controller provisioning to built-in domain `Administrator`, because local `vagrant` is unavailable on DCs.
- Moved guest script root from the unreliable VirtualBox shared-folder reparse point to `C:\LabProvisioning`.
- Patched PowerShell idempotency where AD cmdlets threw on missing OUs/PSOs despite intended missing-object handling.
- Used ADSI for same-domain group membership updates where the child DC's global catalog readiness caused `Add-ADGroupMember` failures.
- Patched Sysmon deployment to invoke `Sysmon64.exe` through `Start-Process` so native executable output does not become a PowerShell `NativeCommandError`.

## Logs

- Child recovery: `logs/playbook-child_domain-recovery-*`, `logs/winterfell-reboot-after-childpromo-*`.
- Domain join: `logs/playbook-domain_join-*`, `logs/verify-domain_join-*`.
- Identity: `logs/playbook-identity-retry7-*`.
- Vulnerabilities: `logs/playbook-vulnerabilities-clean-*`.
- Sysmon: `logs/playbook-sysmon-deploy-retry-*`.
- Final validation: `logs/final-validation-dcs-*`, `logs/final-validation-allhosts-*`.

## Snapshot Handoff

Claude can take baseline snapshots now.
