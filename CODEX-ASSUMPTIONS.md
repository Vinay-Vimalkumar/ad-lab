# Codex Assumptions

- Treating `C:\Users\vinay\Downloads\ad-lab` as the active repository root because the provided environment points there and `C:\Users\vinay\ad-lab` does not exist.
- Claude-owned markdown/documentation paths are read-only for Codex unless the user explicitly listed the file as a Codex deliverable.
- `detection/kql-queries.md` and the full `attacks/*.md` set appeared after initial inspection; Codex detection content was updated to mirror the final KQL attack list and logic.
- `hardening/hardening.md` appeared after the initial hardening script pass; compatibility scripts were added so every hardening guide script link resolves while preserving the explicit user-requested script names.
- Vagrant box versions are pinned to `gusztavvargadr/windows-server-2022-standard` `2601.0.0` and `gusztavvargadr/windows-10-enterprise` `2511.0.0`, based on the provider pages checked during this session and annotated as checked on `2026-05-17`.
- All lab credentials are intentionally insecure and represented through Ansible Vault variables or placeholders such as `{{LAB_PASSWORD}}`.
- For Phase 1/2 execution, Codex treated Claude's exact `PHASE 1 COMPLETE: 5/5 VMs up` marker as the gate for WinRM authentication and Phase 2 playbook execution. That marker was never posted before Claude reported the VirtualBox Hyper-V/NEM boot blocker.
- Corrected an initial WSL ping parsing mistake during Phase 1 monitoring: `100% packet loss` contains the substring `0% packet loss`, so later probes use a stricter `,\s*0% packet loss` match. The corrected probe showed all VM IPs down from WSL after Claude's failed kingslanding boot.
- After WSL2 became unsuitable for Option B, Codex used the repo's `ansible-control` Ubuntu VM as the only Ansible control plane for live Phase 2 execution.
- After DC promotion, Codex used built-in domain `Administrator` for controller-side WinRM because the original local `vagrant` account is unavailable on domain controllers.
- `C:\infrastructure\provisioning` resolves to a VirtualBox shared-folder reparse point on Windows guests; live provisioning scripts were staged under `C:\LabProvisioning\scripts` instead for reliable execution as domain Administrator.
- Child-domain global catalog readiness lagged immediately after promotion, so same-domain group membership mutations were implemented with ADSI where AD cmdlets attempted global catalog verification.
