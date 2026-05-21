#requires -version 5.1
<#
Purpose: Compatibility entrypoint for configuring Authentication Policies and Silos.
Prerequisites: Run with Domain Admin rights and validate a break-glass account first.
Expected runtime: 1-2 minutes in the lab.
What it changes: Delegates to configure-auth-policies.ps1.
Rollback procedure: Disable or remove the created authentication policy silo assignments.
#>
[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [object[]]$RemainingArguments
)

$ErrorActionPreference = 'Stop'
$LogRoot = 'C:\LabProvisioning\logs'
New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
Add-Content -Path (Join-Path $LogRoot 'configure-auth-policy-silos-wrapper.log') -Value ("{0} [INFO] Delegating to configure-auth-policies.ps1" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
& (Join-Path $PSScriptRoot 'configure-auth-policies.ps1') @RemainingArguments
