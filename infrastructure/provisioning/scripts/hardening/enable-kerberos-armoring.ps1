#requires -version 5.1
<#
.SYNOPSIS
Enables Kerberos armoring support locally and optionally through a domain GPO.

Purpose:
  Enable Kerberos FAST/armoring support for clients and domain controllers in the lab.

Prerequisites:
  Run from an elevated Windows PowerShell 5.1 session.
  For domain GPO creation, run on a domain-joined host with ActiveDirectory and GroupPolicy modules.

Expected runtime:
  Less than 1 minute for local settings; 1-3 minutes when creating/linking the GPO.

What it changes:
  Sets local Kerberos client and KDC policy registry values to support claims, compound auth, and armoring.
  Unless -SkipDomainGpo is supplied, creates or updates a LAB - Kerberos Armoring GPO when AD/GPO modules are available.

Rollback procedure:
  Remove or set EnableCbacAndArmor to 0 under the local Kerberos and KDC policy registry keys.
  Unlink or remove the LAB - Kerberos Armoring GPO if it was created.
#>

[CmdletBinding()]
param(
    [string]$TargetDistinguishedName,
    [string]$GpoName = 'LAB - Kerberos Armoring',
    [switch]$SkipDomainGpo,
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

function Try-ConfigureDomainGpo {
    if ($SkipDomainGpo) {
        Write-Log 'Skipping domain GPO configuration because -SkipDomainGpo was supplied.'
        return
    }

    if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
        Write-Log 'ActiveDirectory module is not available; domain GPO configuration skipped.' 'WARN'
        return
    }

    if (-not (Get-Module -ListAvailable -Name GroupPolicy)) {
        Write-Log 'GroupPolicy module is not available; domain GPO configuration skipped.' 'WARN'
        return
    }

    Import-Module ActiveDirectory -ErrorAction Stop
    Import-Module GroupPolicy -ErrorAction Stop

    $domain = Get-ADDomain -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($TargetDistinguishedName)) {
        $TargetDistinguishedName = $domain.DistinguishedName
    }

    $gpo = Get-GPO -Name $GpoName -ErrorAction SilentlyContinue
    if (-not $gpo) {
        New-GPO -Name $GpoName -Comment 'Enables Kerberos armoring support for the AD lab.' -ErrorAction Stop | Out-Null
        Write-Log "Created GPO '$GpoName'."
    } else {
        Write-Log "GPO '$GpoName' already exists."
    }

    $kdcKey = 'HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\System\Kdc\Parameters'
    $clientKey = 'HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\System\Kerberos\Parameters'
    Set-GPRegistryValue -Name $GpoName -Key $kdcKey -ValueName 'EnableCbacAndArmor' -Type DWord -Value 1 -ErrorAction Stop | Out-Null
    Set-GPRegistryValue -Name $GpoName -Key $clientKey -ValueName 'EnableCbacAndArmor' -Type DWord -Value 1 -ErrorAction Stop | Out-Null
    Write-Log "Set Kerberos armoring registry policy values in GPO '$GpoName'."

    $inheritance = Get-GPInheritance -Target $TargetDistinguishedName -ErrorAction Stop
    $existing = $inheritance.GpoLinks | Where-Object { $_.DisplayName -eq $GpoName }
    if ($existing) {
        Write-Log "GPO '$GpoName' is already linked to $TargetDistinguishedName."
        return
    }

    New-GPLink -Name $GpoName -Target $TargetDistinguishedName -LinkEnabled Yes -ErrorAction Stop | Out-Null
    Write-Log "Linked GPO '$GpoName' to $TargetDistinguishedName."
}

try {
    Initialize-Log -Root $LogRoot
    Write-Log 'Starting Kerberos armoring configuration.'
    Assert-Administrator

    Set-RegistryDword -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Kdc\Parameters' -Name 'EnableCbacAndArmor' -Value 1
    Set-RegistryDword -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Kerberos\Parameters' -Name 'EnableCbacAndArmor' -Value 1
    Try-ConfigureDomainGpo

    Write-Log 'Run gpupdate or reboot target systems to apply Kerberos armoring policy.' 'WARN'
    Write-Log 'Completed Kerberos armoring configuration.'
} catch {
    if ($script:LogPath) {
        Write-Log "FAILED: $($_.Exception.Message)" 'ERROR'
        if ($_.ScriptStackTrace) {
            Write-Log $_.ScriptStackTrace 'ERROR'
        }
    }
    throw
}
