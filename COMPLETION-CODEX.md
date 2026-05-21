# Codex Completion

## Files Written

- `.yamllint` - Yamllint project policy used for Ansible and Sigma YAML validation.
- `CODEX-ASSUMPTIONS.md` - Codex-owned assumptions and late-arriving Claude dependency notes.
- `infrastructure/Vagrantfile` - Five-VM VirtualBox/Vagrant lab definition with WinRM bootstrap, Ansible provisioning, and baseline snapshot trigger.
- `infrastructure/provisioning/ansible/ansible.cfg` - WinRM-oriented Ansible defaults.
- `infrastructure/provisioning/ansible/collections/requirements.yml` - Required `ansible.windows`, `community.windows`, and `microsoft.ad` collections.
- `infrastructure/provisioning/ansible/group_vars/all.yml` - Shared domain, IP, WinRM, and password variable references.
- `infrastructure/provisioning/ansible/inventory.yml` - Static inventory for kingslanding, castelblack, winterfell, meereen, and braavos.
- `infrastructure/provisioning/ansible/site.yml` - Ordered orchestration playbook with promotion serialization and tags.
- `infrastructure/provisioning/ansible/vault.yml.example` - Ansible Vault password variable template.
- `infrastructure/provisioning/ansible/roles/common/tasks/main.yml` - Common hostname, DNS, and lab-only WinRM posture.
- `infrastructure/provisioning/ansible/roles/forest_root/tasks/main.yml` - Root forest feature install, idempotency check, promotion, and lab admin creation.
- `infrastructure/provisioning/ansible/roles/child_domain/tasks/main.yml` - Child domain feature install, DNS prep, idempotent promotion, and child admin creation.
- `infrastructure/provisioning/ansible/roles/domain_join/tasks/main.yml` - Domain join tasks for member systems.
- `infrastructure/provisioning/ansible/roles/users_and_ous/tasks/main.yml` - Script-backed OU, group, user, and Domain Admin creation role.
- `infrastructure/provisioning/ansible/roles/service_accounts/tasks/main.yml` - Script-backed Kerberoastable SPN service account role.
- `infrastructure/provisioning/ansible/roles/asrep_accounts/tasks/main.yml` - Script-backed AS-REP roastable account flag role.
- `infrastructure/provisioning/ansible/roles/delegation_accounts/tasks/main.yml` - Script-backed unconstrained delegation account flag role.
- `infrastructure/provisioning/ansible/roles/vulnerable_gpos/tasks/main.yml` - Script-backed vulnerable GPO role.
- `infrastructure/provisioning/ansible/roles/acl_misconfigurations/tasks/main.yml` - Script-backed BloodHound ACL path role.
- `infrastructure/provisioning/scripts/create-users.ps1` - Idempotent OU, group, 35-user, and Domain Admin provisioning.
- `infrastructure/provisioning/scripts/create-service-accounts.ps1` - Idempotent SPN account provisioning for the four Kerberoastable accounts.
- `infrastructure/provisioning/scripts/set-uac-flags.ps1` - Idempotent AS-REP and unconstrained delegation UAC flag provisioning.
- `infrastructure/provisioning/scripts/apply-vulnerable-gpos.ps1` - Idempotent anonymous LDAP, SMBv1, NTLMv1, LLMNR, Print Spooler, and Finance weak-policy provisioning.
- `infrastructure/provisioning/scripts/create-acl-paths.ps1` - Idempotent HR GenericWrite, ServiceAccounts WriteDACL, and ForceChangePassword ACL provisioning.
- `infrastructure/provisioning/scripts/hardening/harden-tier0.ps1` - Tier 0 OU/group and delegation protection hardening.
- `infrastructure/provisioning/scripts/hardening/deploy-laps.ps1` - Windows LAPS deployment helper.
- `infrastructure/provisioning/scripts/hardening/enable-smb-signing.ps1` - SMB signing enforcement helper.
- `infrastructure/provisioning/scripts/hardening/enable-ldap-signing.ps1` - LDAP signing and channel binding helper.
- `infrastructure/provisioning/scripts/hardening/disable-smbv1.ps1` - SMBv1 disablement helper.
- `infrastructure/provisioning/scripts/hardening/disable-ntlmv1.ps1` - LM/NTLMv1 disablement helper.
- `infrastructure/provisioning/scripts/hardening/configure-auth-policies.ps1` - Authentication policy and silo helper.
- `infrastructure/provisioning/scripts/hardening/enable-protected-users.ps1` - Protected Users membership helper.
- `infrastructure/provisioning/scripts/hardening/enable-kerberos-armoring.ps1` - Kerberos armoring helper.
- `infrastructure/provisioning/scripts/hardening/add-protected-users.ps1` - Compatibility wrapper for Claude's Protected Users script link.
- `infrastructure/provisioning/scripts/hardening/deploy-windows-laps.ps1` - Compatibility wrapper for Claude's Windows LAPS script link.
- `infrastructure/provisioning/scripts/hardening/require-smb-signing.ps1` - Compatibility wrapper for Claude's SMB signing script link.
- `infrastructure/provisioning/scripts/hardening/require-ldap-signing-cbt.ps1` - Compatibility wrapper for Claude's LDAP signing/CBT script link.
- `infrastructure/provisioning/scripts/hardening/configure-auth-policy-silos.ps1` - Compatibility wrapper for Claude's auth silo script link.
- `infrastructure/provisioning/scripts/hardening/restrict-ntlm.ps1` - Compatibility wrapper for Claude's NTLM script link.
- `infrastructure/provisioning/scripts/hardening/disable-llmnr-nbtns.ps1` - LLMNR and NBT-NS disablement helper.
- `infrastructure/provisioning/scripts/hardening/disable-spooler-dc.ps1` - DC Print Spooler disablement helper.
- `infrastructure/provisioning/scripts/hardening/restrict-anonymous-ldap.ps1` - Anonymous LDAP/SAM enumeration hardening helper.
- `infrastructure/provisioning/scripts/hardening/apply-fine-grained-password-policy.ps1` - Finance fine-grained password policy hardening helper.
- `infrastructure/provisioning/scripts/hardening/remove-unconstrained-delegation.ps1` - Unconstrained delegation remediation helper.
- `infrastructure/provisioning/scripts/hardening/migrate-to-gmsa.ps1` - gMSA replacement account helper for service-account migration.
- `infrastructure/provisioning/scripts/hardening/enforce-aes-kerberos.ps1` - AES Kerberos encryption type helper.
- `infrastructure/provisioning/scripts/hardening/remediate-dangerous-acls.ps1` - Dangerous ACL remediation helper.
- `detection/sysmon-config.xml` - SwiftOnSecurity-inspired Sysmon configuration with AD attack detections and reproducibility commit reference.
- `detection/sigma-rules/01-bloodhound-enumeration.yaml` - Sigma rule for BloodHound enumeration.
- `detection/sigma-rules/02-kerberoasting.yaml` - Sigma rule for Kerberoasting.
- `detection/sigma-rules/03-asrep-roasting.yaml` - Sigma rule for AS-REP roasting.
- `detection/sigma-rules/04-ntlm-relay.yaml` - Sigma rule for NTLM relay.
- `detection/sigma-rules/05-pass-the-hash.yaml` - Sigma rule for Pass-the-Hash.
- `detection/sigma-rules/06-dcsync.yaml` - Sigma rule for DCSync.
- `detection/sigma-rules/07-golden-ticket.yaml` - Sigma rule for Golden Ticket.
- `detection/sigma-rules/08-silver-ticket.yaml` - Sigma rule for Silver Ticket.
- `detection/sigma-rules/09-unconstrained-delegation.yaml` - Sigma rule for unconstrained delegation abuse.
- `detection/sigma-rules/10-cross-forest-trust-abuse.yaml` - Sigma rule for cross-forest trust abuse.
- `detection/splunk-queries.md` - Splunk SPL queries mirrored from Claude's KQL catalog.
- `detection/elastic-queries.md` - Kibana KQL and Elasticsearch Query DSL mirrored from Claude's KQL catalog.
- `COMPLETION-CODEX.md` - This Codex completion ledger.

## Assumptions

- The active repository is `C:\Users\vinay\Downloads\ad-lab` because that is the provided working directory.
- Claude-owned documentation appeared during execution; Codex read it only to align machine-readable outputs.
- Detection files were rewritten after `detection/kql-queries.md` appeared so Sigma, Splunk, and Elastic logic match Claude's final 10-attack catalog.
- Hardening compatibility scripts were added after `hardening/hardening.md` appeared so every referenced implementation link resolves.
- Vagrant and VirtualBox are not on this host PATH, so `vagrant validate` could not be executed here.
- `xmllint` could not be installed in WSL without sudo credentials; XML was parsed with Python's XML parser instead.

## Validation

- `yamllint infrastructure/provisioning/ansible detection/sigma-rules .yamllint` passed.
- `sigma check detection/sigma-rules/*.yaml` passed with 0 errors, 0 condition errors, and 0 issues.
- `ansible-galaxy collection install -r collections/requirements.yml` installed required collections in WSL.
- `ansible-playbook --syntax-check -i inventory.yml site.yml -e vault_lab_password=...` passed.
- `ansible-lint site.yml` passed at the production profile.
- PowerShell parser validation passed for all provisioning and hardening scripts.
- `Invoke-ScriptAnalyzer -Severity Error` passed for all provisioning and hardening scripts.
- `detection/sysmon-config.xml` parsed successfully as XML.
- All 10 Elasticsearch Query DSL JSON blocks parsed successfully.
- `ruby -c infrastructure/Vagrantfile` returned `Syntax OK`.
- `git diff --check` passed.

## Not Run

- `vagrant up` was intentionally not run per user instruction.
- `vagrant validate` was not run because `vagrant` is not installed or not on PATH in this environment.

## Phase 2 Live Addendum

- `PHASE2-STATUS.md` - Live coordination log for child-domain recovery, remaining role execution, Sysmon deployment, and snapshot handoff.
- `PHASE2-CODEX-REPORT.md` - Rewritten with the completed Phase 2 execution report and final validation results.
- `CODEX-ASSUMPTIONS.md` - Updated with the control-node, post-promotion credential, guest script-root, and ADSI membership assumptions discovered during live recovery.
- `infrastructure/provisioning/ansible/group_vars/all.yml` - Moved guest provisioning root to `C:\LabProvisioning`.
- `infrastructure/provisioning/ansible/group_vars/all/main.yml` - Kept duplicate group-vars source aligned with `C:\LabProvisioning`.
- `infrastructure/provisioning/ansible/roles/common/tasks/main.yml` - Added script staging and DNS dynamic-registration cleanup.
- `infrastructure/provisioning/ansible/roles/forest_root/tasks/main.yml` - Added durable root DC DNS record cleanup and post-promotion `Administrator` credentials.
- `infrastructure/provisioning/ansible/roles/child_domain/tasks/main.yml` - Added durable child DC DNS cleanup and recovery-safe child admin creation.
- `infrastructure/provisioning/ansible/roles/domain_join/tasks/main.yml` - Switched domain join credential to built-in domain `Administrator`.
- `infrastructure/provisioning/ansible/roles/*/tasks/main.yml` - Hardened script wrappers for live execution from `C:\LabProvisioning`.
- `infrastructure/provisioning/scripts/create-users.ps1` - Patched missing-OU handling and same-domain group membership idempotency.
- `infrastructure/provisioning/scripts/create-service-accounts.ps1` - Patched same-domain service-account group membership idempotency.
- `infrastructure/provisioning/scripts/apply-vulnerable-gpos.ps1` - Patched missing-PSO handling and Finance group membership idempotency.
- `infrastructure/provisioning/ansible/sysmon-deploy.yml` - Patched Sysmon installation to use `Start-Process` and exit-code checks.
- `logs/*` - Phase 2 execution, retry, recovery, and final validation logs.

Phase 2 validation completed from `ansible-control`: all ordered roles ran cleanly after recovery, Sysmon is running on all five VMs, and baseline Event ID 1 process-creation events were captured.
