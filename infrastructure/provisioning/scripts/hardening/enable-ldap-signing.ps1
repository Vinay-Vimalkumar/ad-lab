#requires -version 5.1
<#
.SYNOPSIS
Requires LDAP signing for the local LDAP client and, on domain controllers, the LDAP server.

Purpose:
  Reduce credential relay and tampering risk against LDAP by requiring signed binds.

Prerequisites:
  Run from an elevated Windows PowerShell 5.1 session on each target host.
  Run on domain controllers to apply the LDAP server signing requirement.

Expected runtime:
  Less than 1 minute per host.

What it changes:
  Sets LDAPClientIntegrity to Require signing on the local machine.
  Sets LDAPServerIntegrity to Require signing when the NTDS service exists.

Rollback procedure:
  Set LDAPClientIntegrity to 1 for negotiate signing or 0 for none.
  On domain controllers, set LDAPServerIntegrity to 1, then reboot or restart directory services in maintenance.
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
    Write-Log 'Starting LDAP signing hardening.'
    Assert-Administrator

    Set-RegistryDword -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\ldap\Parameters' -Name 'LDAPClientIntegrity' -Value 2

    $ntdsService = Get-Service -Name NTDS -ErrorAction SilentlyContinue
    if ($ntdsService) {
        Set-RegistryDword -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\NTDS\Parameters' -Name 'LDAPServerIntegrity' -Value 2
        Write-Log 'Configured LDAP server signing for this domain controller.'
    } else {
        Write-Log 'NTDS service not found. LDAP server signing was skipped because this host is not a domain controller.' 'WARN'
    }

    Write-Log 'A reboot or service maintenance window may be required for all LDAP signing changes to take effect.' 'WARN'
    Write-Log 'Completed LDAP signing hardening.'
} catch {
    if ($script:LogPath) {
        Write-Log "FAILED: $($_.Exception.Message)" 'ERROR'
        if ($_.ScriptStackTrace) {
            Write-Log $_.ScriptStackTrace 'ERROR'
        }
    }
    throw
}
