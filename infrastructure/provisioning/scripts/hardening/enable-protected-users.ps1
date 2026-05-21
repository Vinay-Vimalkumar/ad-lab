#requires -version 5.1
<#
.SYNOPSIS
Adds eligible privileged users to the Protected Users group.

Purpose:
  Apply stronger authentication protections to interactive privileged accounts.

Prerequisites:
  Run from an elevated Windows PowerShell 5.1 session with the ActiveDirectory module installed.
  Domain controllers must support the Protected Users group.
  Validate service account compatibility before using -IncludeServiceAccounts.

Expected runtime:
  1-3 minutes in a small lab domain.

What it changes:
  Enumerates enabled user members of configured privileged groups.
  Adds eligible users to the domain Protected Users group.
  Skips disabled users and SPN-bearing accounts by default.

Rollback procedure:
  Remove affected users from the Protected Users group with Remove-ADGroupMember.
#>

[CmdletBinding()]
param(
    [string[]]$SourceGroups = @('Domain Admins', 'Enterprise Admins', 'Schema Admins', 'Tier 0 Admins'),
    [switch]$IncludeServiceAccounts,
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

function Import-RequiredModule {
    param([Parameter(Mandatory = $true)][string]$Name)

    if (-not (Get-Module -ListAvailable -Name $Name)) {
        throw "Required PowerShell module '$Name' is not installed."
    }

    Import-Module $Name -ErrorAction Stop
}

try {
    Initialize-Log -Root $LogRoot
    Write-Log 'Starting Protected Users configuration.'
    Assert-Administrator
    Import-RequiredModule -Name ActiveDirectory

    $protectedUsers = Get-ADGroup -Identity 'Protected Users' -ErrorAction Stop
    $currentMembers = @()
    try {
        $currentMembers = @(Get-ADGroupMember -Identity $protectedUsers.DistinguishedName -ErrorAction Stop | ForEach-Object { $_.DistinguishedName })
    } catch {
        $currentMembers = @()
    }

    $seen = @{}
    foreach ($groupName in $SourceGroups) {
        $sourceGroup = Get-ADGroup -Identity $groupName -ErrorAction SilentlyContinue
        if (-not $sourceGroup) {
            Write-Log "Source group '$groupName' was not found; skipping." 'WARN'
            continue
        }

        $members = @(Get-ADGroupMember -Identity $sourceGroup.DistinguishedName -Recursive -ErrorAction Stop | Where-Object { $_.objectClass -eq 'user' })
        foreach ($member in $members) {
            if ($seen.ContainsKey($member.DistinguishedName)) {
                continue
            }

            $seen[$member.DistinguishedName] = $true
            $user = Get-ADUser -Identity $member.DistinguishedName -Properties Enabled,ServicePrincipalName -ErrorAction Stop
            if ($user.Enabled -ne $true) {
                Write-Log "Skipping disabled user '$($user.SamAccountName)'."
                continue
            }

            if (($user.ServicePrincipalName) -and (-not $IncludeServiceAccounts)) {
                Write-Log "Skipping '$($user.SamAccountName)' because it has SPNs. Use -IncludeServiceAccounts to include service accounts." 'WARN'
                continue
            }

            if ($currentMembers -contains $user.DistinguishedName) {
                Write-Log "User '$($user.SamAccountName)' is already a member of Protected Users."
                continue
            }

            Add-ADGroupMember -Identity $protectedUsers.DistinguishedName -Members $user.DistinguishedName -ErrorAction Stop
            $currentMembers += $user.DistinguishedName
            Write-Log "Added '$($user.SamAccountName)' to Protected Users."
        }
    }

    Write-Log 'Completed Protected Users configuration.'
} catch {
    if ($script:LogPath) {
        Write-Log "FAILED: $($_.Exception.Message)" 'ERROR'
        if ($_.ScriptStackTrace) {
            Write-Log $_.ScriptStackTrace 'ERROR'
        }
    }
    throw
}
