#requires -version 5.1
<#
.SYNOPSIS
Requires SMB signing for the local SMB server and client.

Purpose:
  Reduce relay and tampering risk by requiring SMB message signing.

Prerequisites:
  Run from an elevated Windows PowerShell 5.1 session on each target host or through software deployment.

Expected runtime:
  Less than 1 minute per host.

What it changes:
  Sets LanmanServer and LanmanWorkstation registry values to enable and require SMB security signatures.
  Optionally restarts SMB-related services when -RestartServices is supplied.

Rollback procedure:
  Set RequireSecuritySignature to 0 under the LanmanServer and LanmanWorkstation Parameters keys,
  then restart SMB-related services or reboot.
#>

[CmdletBinding()]
param(
    [switch]$RestartServices,
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
    Write-Log 'Starting SMB signing hardening.'
    Assert-Administrator

    $serverPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters'
    $clientPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters'

    Set-RegistryDword -Path $serverPath -Name 'EnableSecuritySignature' -Value 1
    Set-RegistryDword -Path $serverPath -Name 'RequireSecuritySignature' -Value 1
    Set-RegistryDword -Path $clientPath -Name 'EnableSecuritySignature' -Value 1
    Set-RegistryDword -Path $clientPath -Name 'RequireSecuritySignature' -Value 1

    if ($RestartServices) {
        foreach ($serviceName in @('LanmanServer', 'LanmanWorkstation')) {
            $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
            if ($service) {
                Write-Log "Restarting service $serviceName."
                Restart-Service -Name $serviceName -Force -ErrorAction Stop
            }
        }
    } else {
        Write-Log 'SMB services were not restarted. Reboot or restart LanmanServer/LanmanWorkstation to apply everywhere.' 'WARN'
    }

    Write-Log 'Completed SMB signing hardening.'
} catch {
    if ($script:LogPath) {
        Write-Log "FAILED: $($_.Exception.Message)" 'ERROR'
        if ($_.ScriptStackTrace) {
            Write-Log $_.ScriptStackTrace 'ERROR'
        }
    }
    throw
}
