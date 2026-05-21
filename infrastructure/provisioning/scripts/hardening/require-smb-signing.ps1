#requires -version 5.1
<#
Purpose: Compatibility entrypoint for requiring SMB signing.
Prerequisites: Run locally as Administrator or deploy through GPO.
Expected runtime: Under 1 minute.
What it changes: Delegates to enable-smb-signing.ps1.
Rollback procedure: Set SMB client/server RequireSecuritySignature values back to 0.
#>
[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [object[]]$RemainingArguments
)

$ErrorActionPreference = 'Stop'
$LogRoot = 'C:\LabProvisioning\logs'
New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
Add-Content -Path (Join-Path $LogRoot 'require-smb-signing-wrapper.log') -Value ("{0} [INFO] Delegating to enable-smb-signing.ps1" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
& (Join-Path $PSScriptRoot 'enable-smb-signing.ps1') @RemainingArguments
