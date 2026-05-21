#requires -version 5.1
<#
Purpose: Compatibility entrypoint for adding Tier 0 users to Protected Users.
Prerequisites: Run on a domain-joined host with the ActiveDirectory module and Domain Admin rights.
Expected runtime: Under 1 minute in the lab.
What it changes: Delegates to enable-protected-users.ps1.
Rollback procedure: Remove affected accounts from the Protected Users group.
#>
[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [object[]]$RemainingArguments
)

$ErrorActionPreference = 'Stop'
$LogRoot = 'C:\LabProvisioning\logs'
New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
Add-Content -Path (Join-Path $LogRoot 'add-protected-users-wrapper.log') -Value ("{0} [INFO] Delegating to enable-protected-users.ps1" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
& (Join-Path $PSScriptRoot 'enable-protected-users.ps1') @RemainingArguments
