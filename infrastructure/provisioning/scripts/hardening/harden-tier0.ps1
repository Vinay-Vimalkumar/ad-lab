#requires -version 5.1
<#
.SYNOPSIS
Creates a basic Tier 0 administration structure and marks privileged user accounts as non-delegable.

Purpose:
  Establish a repeatable Tier 0 baseline for the lab domain without moving existing accounts.

Prerequisites:
  Run from an elevated Windows PowerShell 5.1 session with the ActiveDirectory module installed.
  The caller must have rights to create OUs/groups and update privileged user account control flags.

Expected runtime:
  1-3 minutes in a small lab domain.

What it changes:
  Creates OU=Tier 0 with Accounts, Groups, Servers, Service Accounts, and Workstations child OUs.
  Creates the Tier 0 Admins and Tier 0 Service Accounts security groups if they do not already exist.
  Sets AccountNotDelegated on enabled user members of common privileged groups, skipping SPN-bearing
  service accounts unless -IncludeServiceAccounts is specified.

Rollback procedure:
  Remove the created Tier 0 OUs/groups if unused.
  To reverse the account flag, run Set-ADAccountControl -AccountNotDelegated $false for affected users.
#>

[CmdletBinding()]
param(
    [string]$Tier0OuName = 'Tier 0',
    [string[]]$PrivilegedGroups = @('Domain Admins', 'Enterprise Admins', 'Schema Admins'),
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

function Escape-FilterValue {
    param([Parameter(Mandatory = $true)][string]$Value)
    return $Value.Replace("'", "''")
}

function Ensure-OrganizationalUnit {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $safeName = Escape-FilterValue -Value $Name
    $existing = Get-ADOrganizationalUnit -Filter "Name -eq '$safeName'" -SearchBase $Path -SearchScope OneLevel -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Log "OU '$Name' already exists at $($existing.DistinguishedName)."
        return $existing.DistinguishedName
    }

    New-ADOrganizationalUnit -Name $Name -Path $Path -ProtectedFromAccidentalDeletion $true -ErrorAction Stop
    $created = Get-ADOrganizationalUnit -Filter "Name -eq '$safeName'" -SearchBase $Path -SearchScope OneLevel -ErrorAction Stop
    Write-Log "Created OU '$Name' at $($created.DistinguishedName)."
    return $created.DistinguishedName
}

function Ensure-SecurityGroup {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$SamAccountName,
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Description
    )

    $existing = Get-ADGroup -Filter "SamAccountName -eq '$SamAccountName'" -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Log "Group '$Name' already exists at $($existing.DistinguishedName)."
        return
    }

    New-ADGroup -Name $Name -SamAccountName $SamAccountName -GroupCategory Security -GroupScope Global -Path $Path -Description $Description -ErrorAction Stop
    Write-Log "Created security group '$Name' in $Path."
}

function Set-PrivilegedUsersNonDelegable {
    param([string[]]$Groups)

    $seen = @{}
    foreach ($groupName in $Groups) {
        try {
            $group = Get-ADGroup -Identity $groupName -ErrorAction Stop
        } catch {
            Write-Log "Privileged group '$groupName' was not found; skipping. $($_.Exception.Message)" 'WARN'
            continue
        }

        Write-Log "Reviewing enabled user members of '$($group.Name)' for AccountNotDelegated."
        $members = @(Get-ADGroupMember -Identity $group.DistinguishedName -Recursive -ErrorAction Stop | Where-Object { $_.objectClass -eq 'user' })
        foreach ($member in $members) {
            if ($seen.ContainsKey($member.DistinguishedName)) {
                continue
            }

            $seen[$member.DistinguishedName] = $true
            $user = Get-ADUser -Identity $member.DistinguishedName -Properties AccountNotDelegated,Enabled,ServicePrincipalName -ErrorAction Stop
            if ($user.Enabled -ne $true) {
                Write-Log "Skipping disabled privileged user '$($user.SamAccountName)'."
                continue
            }

            if (($user.ServicePrincipalName) -and (-not $IncludeServiceAccounts)) {
                Write-Log "Skipping '$($user.SamAccountName)' because it has SPNs. Use -IncludeServiceAccounts to include service accounts." 'WARN'
                continue
            }

            if ($user.AccountNotDelegated -eq $true) {
                Write-Log "AccountNotDelegated is already enabled for '$($user.SamAccountName)'."
                continue
            }

            Set-ADAccountControl -Identity $user.DistinguishedName -AccountNotDelegated $true -ErrorAction Stop
            Write-Log "Enabled AccountNotDelegated for '$($user.SamAccountName)'."
        }
    }
}

try {
    Initialize-Log -Root $LogRoot
    Write-Log 'Starting Tier 0 hardening.'
    Assert-Administrator
    Import-RequiredModule -Name ActiveDirectory

    $domain = Get-ADDomain -ErrorAction Stop
    $domainDn = $domain.DistinguishedName
    $tier0Dn = Ensure-OrganizationalUnit -Name $Tier0OuName -Path $domainDn

    $accountsDn = Ensure-OrganizationalUnit -Name 'Accounts' -Path $tier0Dn
    $groupsDn = Ensure-OrganizationalUnit -Name 'Groups' -Path $tier0Dn
    Ensure-OrganizationalUnit -Name 'Servers' -Path $tier0Dn | Out-Null
    Ensure-OrganizationalUnit -Name 'Service Accounts' -Path $tier0Dn | Out-Null
    Ensure-OrganizationalUnit -Name 'Workstations' -Path $tier0Dn | Out-Null

    Ensure-SecurityGroup -Name 'Tier 0 Admins' -SamAccountName 'Tier0Admins' -Path $groupsDn -Description 'Administrative accounts authorized for Tier 0 systems.'
    Ensure-SecurityGroup -Name 'Tier 0 Service Accounts' -SamAccountName 'Tier0SvcAccounts' -Path $groupsDn -Description 'Service accounts authorized for Tier 0 systems.'
    Write-Log "Tier 0 account staging OU is $accountsDn."

    Set-PrivilegedUsersNonDelegable -Groups $PrivilegedGroups
    Write-Log 'Completed Tier 0 hardening.'
} catch {
    if ($script:LogPath) {
        Write-Log "FAILED: $($_.Exception.Message)" 'ERROR'
        if ($_.ScriptStackTrace) {
            Write-Log $_.ScriptStackTrace 'ERROR'
        }
    }
    throw
}
