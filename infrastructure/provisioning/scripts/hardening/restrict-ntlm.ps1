#requires -version 5.1
<#
Purpose: Compatibility entrypoint for blocking LM and NTLMv1.
Prerequisites: Run locally as Administrator or deploy through GPO after NTLM audit.
Expected runtime: Under 1 minute.
What it changes: Delegates to disable-ntlmv1.ps1.
Rollback procedure: Restore LmCompatibilityLevel to the previous audited value.
#>
[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [object[]]$RemainingArguments
)

$ErrorActionPreference = 'Stop'
$LogRoot = 'C:\LabProvisioning\logs'
New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
Add-Content -Path (Join-Path $LogRoot 'restrict-ntlm-wrapper.log') -Value ("{0} [INFO] Delegating to disable-ntlmv1.ps1" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
& (Join-Path $PSScriptRoot 'disable-ntlmv1.ps1') @RemainingArguments
