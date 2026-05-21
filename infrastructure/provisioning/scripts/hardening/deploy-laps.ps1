#requires -version 5.1
<#
.SYNOPSIS
Deploys Windows LAPS prerequisites, permissions, and a baseline domain GPO.

Purpose:
  Enable centralized local administrator password rotation and storage for lab computers.

Prerequisites:
  Run from an elevated Windows PowerShell 5.1 session on a domain-joined management host or DC.
  Requires ActiveDirectory, GroupPolicy, and Windows LAPS PowerShell modules.
  Schema update requires Enterprise Admin and Schema Admin permissions.

Expected runtime:
  2-5 minutes in a small lab domain.

What it changes:
  Extends the AD schema for Windows LAPS if needed.
  Grants computer self-permission on the target OU/domain DN.
  Grants configured principals read/reset permissions for Windows LAPS passwords.
  Creates or updates a LAB - Windows LAPS GPO and links it to the target DN.

Rollback procedure:
  Unlink and remove the LAB - Windows LAPS GPO.
  Remove delegated LAPS ACEs manually if required.
  AD schema extensions are not practically rolled back; disable the policy instead.
#>

[CmdletBinding()]
param(
    [string]$TargetDistinguishedName,
    [string]$GpoName = 'LAB - Windows LAPS',
    [string[]]$PasswordReaderGroups = @('Domain Admins'),
    [int]$PasswordAgeDays = 30,
    [int]$PasswordLength = 20,
    [ValidateRange(1,4)][int]$PasswordComplexity = 4,
    [string]$LocalAdminAccountName = '',
    [switch]$EnablePasswordEncryption,
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

function Assert-CommandAvailable {
    param([Parameter(Mandatory = $true)][string]$Name)

    if (-not (Get-Command -Name $Name -ErrorAction SilentlyContinue)) {
        throw "Required command '$Name' is not available. Install the Windows LAPS management tools."
    }
}

function Ensure-WindowsLapsSchema {
    $rootDse = Get-ADRootDSE -ErrorAction Stop
    $schemaNc = $rootDse.schemaNamingContext
    $lapsAttribute = Get-ADObject -SearchBase $schemaNc -LDAPFilter '(lDAPDisplayName=msLAPS-PasswordExpirationTime)' -ErrorAction SilentlyContinue
    if ($lapsAttribute) {
        Write-Log 'Windows LAPS schema attributes already exist.'
        return
    }

    Write-Log 'Windows LAPS schema attributes not found. Running Update-LapsADSchema.'
    Update-LapsADSchema -Confirm:$false -ErrorAction Stop
    Write-Log 'Windows LAPS schema update completed.'
}

function Ensure-Gpo {
    param([Parameter(Mandatory = $true)][string]$Name)

    $gpo = Get-GPO -Name $Name -ErrorAction SilentlyContinue
    if ($gpo) {
        Write-Log "GPO '$Name' already exists."
        return
    }

    New-GPO -Name $Name -Comment 'Configures Windows LAPS for the AD lab.' -ErrorAction Stop | Out-Null
    Write-Log "Created GPO '$Name'."
}

function Set-GpoDword {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][string]$ValueName,
        [Parameter(Mandatory = $true)][int]$Value
    )

    Set-GPRegistryValue -Name $Name -Key $Key -ValueName $ValueName -Type DWord -Value $Value -ErrorAction Stop | Out-Null
    Write-Log "Set GPO registry value $Key\$ValueName to $Value."
}

function Set-GpoString {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][string]$ValueName,
        [Parameter(Mandatory = $true)][string]$Value
    )

    Set-GPRegistryValue -Name $Name -Key $Key -ValueName $ValueName -Type String -Value $Value -ErrorAction Stop | Out-Null
    Write-Log "Set GPO registry value $Key\$ValueName."
}

function Ensure-GpoLink {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Target
    )

    $inheritance = Get-GPInheritance -Target $Target -ErrorAction Stop
    $existing = $inheritance.GpoLinks | Where-Object { $_.DisplayName -eq $Name }
    if ($existing) {
        Write-Log "GPO '$Name' is already linked to $Target."
        return
    }

    New-GPLink -Name $Name -Target $Target -LinkEnabled Yes -ErrorAction Stop | Out-Null
    Write-Log "Linked GPO '$Name' to $Target."
}

try {
    Initialize-Log -Root $LogRoot
    Write-Log 'Starting Windows LAPS deployment.'
    Assert-Administrator
    Import-RequiredModule -Name ActiveDirectory
    Import-RequiredModule -Name GroupPolicy
    Import-RequiredModule -Name LAPS
    Assert-CommandAvailable -Name Update-LapsADSchema

    $domain = Get-ADDomain -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($TargetDistinguishedName)) {
        $TargetDistinguishedName = $domain.DistinguishedName
    }

    Ensure-WindowsLapsSchema
    Set-LapsADComputerSelfPermission -Identity $TargetDistinguishedName -ErrorAction Stop | Out-Null
    Write-Log "Ensured Windows LAPS computer self-permission on $TargetDistinguishedName."

    foreach ($principal in $PasswordReaderGroups) {
        Set-LapsADReadPasswordPermission -Identity $TargetDistinguishedName -AllowedPrincipals $principal -ErrorAction Stop | Out-Null
        Set-LapsADResetPasswordPermission -Identity $TargetDistinguishedName -AllowedPrincipals $principal -ErrorAction Stop | Out-Null
        Write-Log "Ensured Windows LAPS read/reset permissions for '$principal' on $TargetDistinguishedName."
    }

    Ensure-Gpo -Name $GpoName
    $lapsKey = 'HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\LAPS'
    Set-GpoDword -Name $GpoName -Key $lapsKey -ValueName 'BackupDirectory' -Value 2
    Set-GpoDword -Name $GpoName -Key $lapsKey -ValueName 'PasswordAgeDays' -Value $PasswordAgeDays
    Set-GpoDword -Name $GpoName -Key $lapsKey -ValueName 'PasswordLength' -Value $PasswordLength
    Set-GpoDword -Name $GpoName -Key $lapsKey -ValueName 'PasswordComplexity' -Value $PasswordComplexity

    if ($EnablePasswordEncryption) {
        Set-GpoDword -Name $GpoName -Key $lapsKey -ValueName 'ADPasswordEncryptionEnabled' -Value 1
    } else {
        Set-GpoDword -Name $GpoName -Key $lapsKey -ValueName 'ADPasswordEncryptionEnabled' -Value 0
    }

    if (-not [string]::IsNullOrWhiteSpace($LocalAdminAccountName)) {
        Set-GpoString -Name $GpoName -Key $lapsKey -ValueName 'AdministratorAccountName' -Value $LocalAdminAccountName
    }

    Ensure-GpoLink -Name $GpoName -Target $TargetDistinguishedName
    Write-Log 'Completed Windows LAPS deployment.'
} catch {
    if ($script:LogPath) {
        Write-Log "FAILED: $($_.Exception.Message)" 'ERROR'
        if ($_.ScriptStackTrace) {
            Write-Log $_.ScriptStackTrace 'ERROR'
        }
    }
    throw
}
