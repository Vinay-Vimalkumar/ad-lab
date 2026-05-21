#requires -version 5.1
<#
.SYNOPSIS
Creates a Tier 0 authentication policy and authentication policy silo.

Purpose:
  Prepare AD authentication policy controls for Tier 0 accounts in the lab domain.

Prerequisites:
  Run from an elevated Windows PowerShell 5.1 session with the ActiveDirectory module installed.
  Domain functional level must be Windows Server 2012 R2 or newer.
  Run harden-tier0.ps1 first if you want automatic assignment from the Tier 0 Admins group.

Expected runtime:
  1-3 minutes in a small lab domain.

What it changes:
  Creates or updates a LAB - Tier 0 Admin Authentication Policy with a short user TGT lifetime.
  Creates or updates a LAB - Tier 0 Authentication Silo and associates it with the policy.
  Grants and assigns the silo to user/computer members of the target Tier 0 group when present.

Rollback procedure:
  Run Set-ADAccountAuthenticationPolicySilo -AuthenticationPolicySilo $null for assigned accounts.
  Remove the authentication policy silo and authentication policy after assignments are cleared.
#>

[CmdletBinding()]
param(
    [string]$PolicyName = 'LAB - Tier 0 Admin Authentication Policy',
    [string]$SiloName = 'LAB - Tier 0 Authentication Silo',
    [string]$TargetGroupName = 'Tier 0 Admins',
    [int]$UserTgtLifetimeMins = 120,
    [switch]$Enforce,
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

function Assert-AuthenticationPolicySupport {
    $domain = Get-ADDomain -ErrorAction Stop
    $mode = $domain.DomainMode.ToString()
    if ($mode -notmatch '2012R2|2016|2019|2022|2025|Threshold') {
        throw "Domain functional level '$mode' does not support authentication policies. Raise it to Windows Server 2012 R2 or newer."
    }

    Write-Log "Domain functional level '$mode' supports authentication policies."
}

function Ensure-AuthenticationPolicy {
    $policy = Get-ADAuthenticationPolicy -Identity $PolicyName -ErrorAction SilentlyContinue
    if ($policy) {
        Set-ADAuthenticationPolicy -Identity $PolicyName -UserTGTLifetimeMins $UserTgtLifetimeMins -Enforce:$Enforce.IsPresent -ErrorAction Stop
        Write-Log "Updated authentication policy '$PolicyName'. Enforce=$($Enforce.IsPresent)."
        return
    }

    if ($Enforce) {
        New-ADAuthenticationPolicy -Name $PolicyName -Description 'Tier 0 admin authentication policy for the AD lab.' -UserTGTLifetimeMins $UserTgtLifetimeMins -Enforce -ErrorAction Stop | Out-Null
    } else {
        New-ADAuthenticationPolicy -Name $PolicyName -Description 'Tier 0 admin authentication policy for the AD lab.' -UserTGTLifetimeMins $UserTgtLifetimeMins -ErrorAction Stop | Out-Null
    }

    Write-Log "Created authentication policy '$PolicyName'. Enforce=$($Enforce.IsPresent)."
}

function Ensure-AuthenticationSilo {
    $silo = Get-ADAuthenticationPolicySilo -Identity $SiloName -ErrorAction SilentlyContinue
    if ($silo) {
        Set-ADAuthenticationPolicySilo -Identity $SiloName -UserAuthenticationPolicy $PolicyName -ComputerAuthenticationPolicy $PolicyName -ServiceAuthenticationPolicy $PolicyName -Enforce:$Enforce.IsPresent -ErrorAction Stop
        Write-Log "Updated authentication policy silo '$SiloName'. Enforce=$($Enforce.IsPresent)."
        return
    }

    if ($Enforce) {
        New-ADAuthenticationPolicySilo -Name $SiloName -Description 'Tier 0 authentication silo for the AD lab.' -UserAuthenticationPolicy $PolicyName -ComputerAuthenticationPolicy $PolicyName -ServiceAuthenticationPolicy $PolicyName -Enforce -ErrorAction Stop | Out-Null
    } else {
        New-ADAuthenticationPolicySilo -Name $SiloName -Description 'Tier 0 authentication silo for the AD lab.' -UserAuthenticationPolicy $PolicyName -ComputerAuthenticationPolicy $PolicyName -ServiceAuthenticationPolicy $PolicyName -ErrorAction Stop | Out-Null
    }

    Write-Log "Created authentication policy silo '$SiloName'. Enforce=$($Enforce.IsPresent)."
}

function Assign-SiloToTier0Members {
    $group = Get-ADGroup -Identity $TargetGroupName -ErrorAction SilentlyContinue
    if (-not $group) {
        Write-Log "Target group '$TargetGroupName' was not found. Silo assignment skipped." 'WARN'
        return
    }

    $silo = Get-ADAuthenticationPolicySilo -Identity $SiloName -ErrorAction Stop
    $members = @(Get-ADGroupMember -Identity $group.DistinguishedName -Recursive -ErrorAction Stop | Where-Object { $_.objectClass -eq 'user' -or $_.objectClass -eq 'computer' })
    if ($members.Count -eq 0) {
        Write-Log "Target group '$TargetGroupName' has no user or computer members to assign." 'WARN'
        return
    }

    foreach ($member in $members) {
        Grant-ADAuthenticationPolicySiloAccess -Identity $SiloName -Account $member.DistinguishedName -ErrorAction Stop
        $account = Get-ADObject -Identity $member.DistinguishedName -Properties 'msDS-AssignedAuthNPolicySilo' -ErrorAction Stop
        if ($account.'msDS-AssignedAuthNPolicySilo' -eq $silo.DistinguishedName) {
            Write-Log "Account '$($member.Name)' is already assigned to silo '$SiloName'."
            continue
        }

        Set-ADAccountAuthenticationPolicySilo -Identity $member.DistinguishedName -AuthenticationPolicySilo $SiloName -AuthenticationPolicy $PolicyName -ErrorAction Stop
        Write-Log "Granted and assigned silo '$SiloName' to '$($member.Name)'."
    }
}

try {
    Initialize-Log -Root $LogRoot
    Write-Log 'Starting authentication policy configuration.'
    Assert-Administrator
    Import-RequiredModule -Name ActiveDirectory
    Assert-AuthenticationPolicySupport

    Ensure-AuthenticationPolicy
    Ensure-AuthenticationSilo
    Assign-SiloToTier0Members

    if (-not $Enforce) {
        Write-Log 'Authentication policy and silo are configured without enforcement. Re-run with -Enforce after validation to enforce controls.' 'WARN'
    }

    Write-Log 'Completed authentication policy configuration.'
} catch {
    if ($script:LogPath) {
        Write-Log "FAILED: $($_.Exception.Message)" 'ERROR'
        if ($_.ScriptStackTrace) {
            Write-Log $_.ScriptStackTrace 'ERROR'
        }
    }
    throw
}
