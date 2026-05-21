#requires -version 5.1
<#
.SYNOPSIS
Disables SMBv1 server and client components on the local host.

Purpose:
  Remove legacy SMBv1 exposure from lab systems.

Prerequisites:
  Run from an elevated Windows PowerShell 5.1 session on each target host.

Expected runtime:
  1-2 minutes per host.

What it changes:
  Disables the SMB1Protocol Windows optional feature when present.
  Sets LanmanServer SMB1 to disabled.
  Disables the MRxSmb10 client driver and removes it from LanmanWorkstation dependencies.

Rollback procedure:
  Re-enable the SMB1Protocol feature if required, set LanmanServer SMB1 to 1,
  set MRxSmb10 Start to 2 or 3 as appropriate, restore workstation dependencies, then reboot.
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

function Disable-OptionalFeatureIfPresent {
    param([Parameter(Mandatory = $true)][string]$FeatureName)

    if (-not (Get-Command -Name Get-WindowsOptionalFeature -ErrorAction SilentlyContinue)) {
        Write-Log 'Get-WindowsOptionalFeature is not available on this host; skipping optional feature state check.' 'WARN'
        return
    }

    $feature = Get-WindowsOptionalFeature -Online -FeatureName $FeatureName -ErrorAction SilentlyContinue
    if (-not $feature) {
        Write-Log "Optional feature '$FeatureName' was not found; skipping." 'WARN'
        return
    }

    if ($feature.State -eq 'Disabled') {
        Write-Log "Optional feature '$FeatureName' is already disabled."
        return
    }

    Disable-WindowsOptionalFeature -Online -FeatureName $FeatureName -NoRestart -ErrorAction Stop | Out-Null
    Write-Log "Disabled optional feature '$FeatureName'."
}

function Remove-MRxSmb10Dependency {
    $path = 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation'
    if (-not (Test-Path -LiteralPath $path)) {
        Write-Log "Registry key $path was not found; skipping dependency cleanup." 'WARN'
        return
    }

    $current = @()
    try {
        $current = @((Get-ItemProperty -Path $path -Name 'DependOnService' -ErrorAction Stop).DependOnService)
    } catch {
        Write-Log 'LanmanWorkstation DependOnService was not found; skipping dependency cleanup.' 'WARN'
        return
    }

    $updated = @($current | Where-Object { $_ -ne 'MRxSmb10' })
    if ($updated.Count -eq $current.Count) {
        Write-Log 'MRxSmb10 is already absent from LanmanWorkstation dependencies.'
        return
    }

    Set-ItemProperty -Path $path -Name 'DependOnService' -Value $updated -ErrorAction Stop
    Write-Log 'Removed MRxSmb10 from LanmanWorkstation dependencies.'
}

try {
    Initialize-Log -Root $LogRoot
    Write-Log 'Starting SMBv1 disablement.'
    Assert-Administrator

    Disable-OptionalFeatureIfPresent -FeatureName 'SMB1Protocol'
    Set-RegistryDword -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters' -Name 'SMB1' -Value 0
    Set-RegistryDword -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\mrxsmb10' -Name 'Start' -Value 4
    Remove-MRxSmb10Dependency

    Write-Log 'A reboot is recommended to fully unload SMBv1 components.' 'WARN'
    Write-Log 'Completed SMBv1 disablement.'
} catch {
    if ($script:LogPath) {
        Write-Log "FAILED: $($_.Exception.Message)" 'ERROR'
        if ($_.ScriptStackTrace) {
            Write-Log $_.ScriptStackTrace 'ERROR'
        }
    }
    throw
}
