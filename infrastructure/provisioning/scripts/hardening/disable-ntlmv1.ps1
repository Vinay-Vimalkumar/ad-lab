#requires -version 5.1
<#
.SYNOPSIS
Disables LM and NTLMv1 authentication on the local host.

Purpose:
  Force NTLMv2-only behavior and prevent storage of LAN Manager password hashes.

Prerequisites:
  Run from an elevated Windows PowerShell 5.1 session on each target host or through software deployment.
  Validate legacy application compatibility before broad rollout.

Expected runtime:
  Less than 1 minute per host.

What it changes:
  Sets LmCompatibilityLevel to 5.
  Sets NoLMHash to 1.
  Requires NTLMv2 session security and 128-bit encryption for NTLM SSP clients and servers.

Rollback procedure:
  Set LmCompatibilityLevel to 3 for NTLMv2-preferred compatibility.
  Adjust NtlmMinClientSec and NtlmMinServerSec to the previous baseline, then reboot.
#>

[CmdletBinding()]
param(
    [string]$LogRoot = 'C:\LabProvisioning\logs'
)

$ErrorActionPreference = 'Stop'
$script:ScriptFileName = $MyInvocation.MyCommand.Name
$script:LogPath = $null

function Initialize-Log {
    param([string]$Root)

    if (-not (Test-Path -LiteralPath $Root)) {
        New-Item -ItemType Directory -Path $Root -Force | Out-Null
    }

    $scriptName = [System.IO.Path]::GetFileNameWithoutExtension($script:ScriptFileName)
    $script:LogPath = Join-Path $Root ('{0}-{1}.log' -f $scriptName, (Get-Date -Format 'yyyyMMdd-HHmmss'))
    New-Item -ItemType File -Path $script:LogPath -Force | Out-Null
}

function Write-Log {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level = 'INFO'
    )

    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Add-Content -Path $script:LogPath -Value $line
    Write-Host $line
}

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Run this script from an elevated Windows PowerShell session.'
    }
}

function Set-RegistryDword {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][int]$Value
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -Force | Out-Null
        Write-Log "Created registry key $Path."
    }

    $current = $null
    try {
        $current = (Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop).$Name
    } catch {
        $current = $null
    }

    if ($current -eq $Value) {
        Write-Log "Registry value $Path\$Name already equals $Value."
        return
    }

    New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType DWord -Force -ErrorAction Stop | Out-Null
    Write-Log "Set registry value $Path\$Name to $Value."
}

try {
    Initialize-Log -Root $LogRoot
    Write-Log 'Starting NTLMv1 disablement.'
    Assert-Administrator

    $lsaPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'
    $msvPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\MSV1_0'

    Set-RegistryDword -Path $lsaPath -Name 'LmCompatibilityLevel' -Value 5
    Set-RegistryDword -Path $lsaPath -Name 'NoLMHash' -Value 1
    Set-RegistryDword -Path $msvPath -Name 'NtlmMinClientSec' -Value 537395200
    Set-RegistryDword -Path $msvPath -Name 'NtlmMinServerSec' -Value 537395200

    Write-Log 'A reboot is recommended before validating NTLM policy behavior.' 'WARN'
    Write-Log 'Completed NTLMv1 disablement.'
} catch {
    if ($script:LogPath) {
        Write-Log "FAILED: $($_.Exception.Message)" 'ERROR'
        if ($_.ScriptStackTrace) {
            Write-Log $_.ScriptStackTrace 'ERROR'
        }
    }
    throw
}
