#requires -version 5.1
<#
Purpose: Compatibility entrypoint for requiring LDAP signing and channel binding.
Prerequisites: Run on domain controllers as Administrator.
Expected runtime: Under 1 minute per DC.
What it changes: Delegates to enable-ldap-signing.ps1.
Rollback procedure: Restore LDAPServerIntegrity and LdapEnforceChannelBinding registry values.
#>
[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [object[]]$RemainingArguments
)

$ErrorActionPreference = 'Stop'
$LogRoot = 'C:\LabProvisioning\logs'
New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
Add-Content -Path (Join-Path $LogRoot 'require-ldap-signing-cbt-wrapper.log') -Value ("{0} [INFO] Delegating to enable-ldap-signing.ps1" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
& (Join-Path $PSScriptRoot 'enable-ldap-signing.ps1') @RemainingArguments
