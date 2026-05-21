#requires -version 5.1
<#
Purpose: Replace the weak Finance policy with a stronger fine-grained password policy.
Prerequisites: Run with ActiveDirectory module and Domain Admin rights.
Expected runtime: Under 1 minute per domain.
What it changes: Creates or updates a PSO and applies it to the Finance group.
Rollback procedure: Remove the PSO with Remove-ADFineGrainedPasswordPolicy or detach the Finance group subject.
#>
[CmdletBinding()]
param(
    [string]$Domain = (Get-ADDomain).DNSRoot,
    [string]$FinanceGroup = 'Finance',
    [int]$MinPasswordLength = 14
)

$ErrorActionPreference = 'Stop'
$LogRoot = 'C:\LabProvisioning\logs'
$LogPath = Join-Path $LogRoot ("apply-fgpp-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Add-Content -Path $LogPath -Value $line
    Write-Output $line
}

try {
    New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
    Import-Module ActiveDirectory -ErrorAction Stop
    $policyName = 'Finance-PSO'
    $existing = Get-ADFineGrainedPasswordPolicy -Identity $policyName -Server $Domain -ErrorAction SilentlyContinue
    if (-not $existing) {
        New-ADFineGrainedPasswordPolicy -Name $policyName -Server $Domain -Precedence 10 -MinPasswordLength $MinPasswordLength -ComplexityEnabled $true -ReversibleEncryptionEnabled $false -LockoutThreshold 5 -MaxPasswordAge (New-TimeSpan -Days 90) -MinPasswordAge (New-TimeSpan -Days 1) | Out-Null
        Write-Log "Created $policyName in $Domain."
    } else {
        Set-ADFineGrainedPasswordPolicy -Identity $policyName -Server $Domain -MinPasswordLength $MinPasswordLength -ComplexityEnabled $true -ReversibleEncryptionEnabled $false -LockoutThreshold 5
        Write-Log "Updated $policyName in $Domain."
    }
    $group = Get-ADGroup -Identity $FinanceGroup -Server $Domain
    $subjects = Get-ADFineGrainedPasswordPolicySubject -Identity $policyName -Server $Domain
    if (@($subjects | Select-Object -ExpandProperty DistinguishedName) -notcontains $group.DistinguishedName) {
        Add-ADFineGrainedPasswordPolicySubject -Identity $policyName -Subjects $group.DistinguishedName -Server $Domain
    }
} catch {
    Write-Log $_.Exception.Message 'ERROR'
    throw
}
