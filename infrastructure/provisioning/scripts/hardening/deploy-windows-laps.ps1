#requires -version 5.1
<#
Purpose: Compatibility entrypoint for deploying Windows LAPS.
Prerequisites: Run with rights to extend/update LAPS policy and AD permissions.
Expected runtime: 1-3 minutes in the lab.
What it changes: Delegates to deploy-laps.ps1.
Rollback procedure: Unlink the LAPS GPO and remove delegated LAPS readers if required.
#>
[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [object[]]$RemainingArguments
)

$ErrorActionPreference = 'Stop'
$LogRoot = 'C:\LabProvisioning\logs'
New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
Add-Content -Path (Join-Path $LogRoot 'deploy-windows-laps-wrapper.log') -Value ("{0} [INFO] Delegating to deploy-laps.ps1" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
& (Join-Path $PSScriptRoot 'deploy-laps.ps1') @RemainingArguments
