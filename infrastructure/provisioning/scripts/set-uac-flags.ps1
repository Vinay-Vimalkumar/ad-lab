#requires -version 5.1
<#
.SYNOPSIS
Sets intentionally vulnerable UAC-related account flags for the AD lab.

.IDEMPOTENCY
This script only sets the requested vulnerable flags when they are missing. It
does not remove other UserAccountControl bits and does not create accounts.
Missing target accounts are reported with explicit errors so provisioning order
problems are easy to diagnose. Re-running the script leaves already-converged
accounts unchanged.
#>
[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()]
    [string[]]$Domains = @('sevenkingdoms.local', 'north.sevenkingdoms.local'),

    [ValidateSet('All', 'Asrep', 'Delegation')]
    [string]$Mode = 'All'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$LogRoot = 'C:\LabProvisioning\logs'
$LogPath = Join-Path $LogRoot ("set-uac-flags-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))

function Write-Log {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level = 'INFO'
    )

    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Add-Content -Path $LogPath -Value $line
    Write-Host $line
}

function Escape-LdapFilterValue {
    param([Parameter(Mandatory = $true)][string]$Value)

    return $Value.Replace('\', '\5c').Replace('*', '\2a').Replace('(', '\28').Replace(')', '\29').Replace([string][char]0, '\00')
}

function Get-RequiredUser {
    param(
        [Parameter(Mandatory = $true)][string]$SamAccountName,
        [Parameter(Mandatory = $true)][string]$Server
    )

    $escapedSam = Escape-LdapFilterValue -Value $SamAccountName
    $user = Get-ADUser -LDAPFilter "(sAMAccountName=$escapedSam)" -Server $Server -Properties DoesNotRequirePreAuth,TrustedForDelegation,AccountNotDelegated -ErrorAction SilentlyContinue
    if ($null -eq $user) {
        throw "Required user $SamAccountName was not found in $Server. Run create-users.ps1 first."
    }

    return $user
}

function Ensure-DoesNotRequirePreAuth {
    param(
        [Parameter(Mandatory = $true)][string]$SamAccountName,
        [Parameter(Mandatory = $true)][string]$Server
    )

    $user = Get-RequiredUser -SamAccountName $SamAccountName -Server $Server
    if (-not $user.DoesNotRequirePreAuth) {
        Set-ADAccountControl -Identity $user.DistinguishedName -DoesNotRequirePreAuth $true -Server $Server
        Write-Log ("Enabled DONT_REQ_PREAUTH on {0} in {1}" -f $SamAccountName, $Server)
    }
    else {
        Write-Log ("DONT_REQ_PREAUTH already enabled on {0} in {1}" -f $SamAccountName, $Server)
    }
}

function Ensure-UnconstrainedDelegation {
    param(
        [Parameter(Mandatory = $true)][string]$SamAccountName,
        [Parameter(Mandatory = $true)][string]$Server
    )

    $user = Get-RequiredUser -SamAccountName $SamAccountName -Server $Server
    if (-not $user.TrustedForDelegation -or $user.AccountNotDelegated) {
        Set-ADAccountControl -Identity $user.DistinguishedName -AccountNotDelegated $false -TrustedForDelegation $true -Server $Server
        Write-Log ("Enabled unconstrained delegation on {0} in {1}" -f $SamAccountName, $Server)
    }
    else {
        Write-Log ("Unconstrained delegation already enabled on {0} in {1}" -f $SamAccountName, $Server)
    }
}

try {
    New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
    Write-Log 'Starting UAC flag provisioning'

    Import-Module ActiveDirectory -ErrorAction Stop

    $asRepTargets = @(
        @{ Domain = 'sevenkingdoms.local'; Sam = 'jon.snow' },
        @{ Domain = 'sevenkingdoms.local'; Sam = 'arya.stark' },
        @{ Domain = 'sevenkingdoms.local'; Sam = 'sansa.stark' }
    )

    $delegationTargets = @(
        @{ Domain = 'sevenkingdoms.local'; Sam = 'cersei.lannister' },
        @{ Domain = 'north.sevenkingdoms.local'; Sam = 'brandon.stark' }
    )

    if ($Mode -in @('All', 'Asrep')) {
        foreach ($target in $asRepTargets | Where-Object { $Domains -icontains $_.Domain }) {
            Ensure-DoesNotRequirePreAuth -SamAccountName $target.Sam -Server $target.Domain
        }
    }

    if ($Mode -in @('All', 'Delegation')) {
        foreach ($target in $delegationTargets | Where-Object { $Domains -icontains $_.Domain }) {
            Ensure-UnconstrainedDelegation -SamAccountName $target.Sam -Server $target.Domain
        }
    }

    Write-Log 'UAC flag provisioning completed successfully'
}
catch {
    $message = 'UAC flag provisioning failed: {0}' -f $_.Exception.Message
    Write-Log $message 'ERROR'
    if ($_.ScriptStackTrace) {
        Write-Log $_.ScriptStackTrace 'ERROR'
    }
    throw
}
