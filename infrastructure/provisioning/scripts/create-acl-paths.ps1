#requires -version 5.1
<#
.SYNOPSIS
Creates intentionally vulnerable AD ACL paths for the lab.

.IDEMPOTENCY
This script creates missing OU/group containers needed as ACL principals, then
adds only missing explicit allow ACEs. It does not remove or reorder unrelated
ACL entries. Target users for account-specific paths must already exist; missing
users produce informative errors instead of creating partial attack paths.
#>
[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()]
    [string[]]$Domains = @('sevenkingdoms.local', 'north.sevenkingdoms.local'),

    [ValidateNotNullOrEmpty()]
    [string]$PrimaryDomain = 'sevenkingdoms.local'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$LogRoot = 'C:\LabProvisioning\logs'
$LogPath = Join-Path $LogRoot ("create-acl-paths-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))

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

function Ensure-LabOu {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$DomainDn,
        [Parameter(Mandatory = $true)][string]$Server
    )

    $ouDn = 'OU={0},{1}' -f $Name, $DomainDn
    $ou = Get-ADOrganizationalUnit -Identity $ouDn -Server $Server -ErrorAction SilentlyContinue
    if ($null -eq $ou) {
        New-ADOrganizationalUnit -Name $Name -Path $DomainDn -Server $Server -ProtectedFromAccidentalDeletion $false | Out-Null
        Write-Log ("Created OU {0} in {1}" -f $Name, $Server)
    }

    return $ouDn
}

function Ensure-LabGroup {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Server
    )

    $escapedName = Escape-LdapFilterValue -Value $Name
    $group = Get-ADGroup -LDAPFilter "(sAMAccountName=$escapedName)" -Server $Server -Properties objectSid -ErrorAction SilentlyContinue
    if ($null -eq $group) {
        $group = New-ADGroup -Name $Name -SamAccountName $Name -GroupCategory Security -GroupScope Global -Path $Path -Server $Server -PassThru
        Write-Log ("Created security group {0} in {1}" -f $Name, $Server)
        $group = Get-ADGroup -Identity $group.DistinguishedName -Server $Server -Properties objectSid
    }

    return $group
}

function Get-RequiredUser {
    param(
        [Parameter(Mandatory = $true)][string]$SamAccountName,
        [Parameter(Mandatory = $true)][string]$Server
    )

    $escapedSam = Escape-LdapFilterValue -Value $SamAccountName
    $user = Get-ADUser -LDAPFilter "(sAMAccountName=$escapedSam)" -Server $Server -Properties objectSid -ErrorAction SilentlyContinue
    if ($null -eq $user) {
        throw "Required user $SamAccountName was not found in $Server. Run create-users.ps1 before create-acl-paths.ps1."
    }

    return $user
}

function Get-DirectoryEntry {
    param(
        [Parameter(Mandatory = $true)][string]$Server,
        [Parameter(Mandatory = $true)][string]$DistinguishedName
    )

    return New-Object System.DirectoryServices.DirectoryEntry("LDAP://$Server/$DistinguishedName")
}

function Test-AceExists {
    param(
        [Parameter(Mandatory = $true)][System.DirectoryServices.ActiveDirectorySecurity]$Acl,
        [Parameter(Mandatory = $true)][System.Security.Principal.SecurityIdentifier]$Sid,
        [Parameter(Mandatory = $true)][System.DirectoryServices.ActiveDirectoryRights]$Rights,
        [Guid]$ObjectType = [Guid]::Empty
    )

    $rules = $Acl.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier])
    foreach ($rule in $rules) {
        if ($rule.IdentityReference.Value -ne $Sid.Value) {
            continue
        }

        if ($rule.AccessControlType -ne [System.Security.AccessControl.AccessControlType]::Allow) {
            continue
        }

        if (($rule.ActiveDirectoryRights -band $Rights) -ne $Rights) {
            continue
        }

        if ($ObjectType -ne [Guid]::Empty -and $rule.ObjectType -ne $ObjectType) {
            continue
        }

        return $true
    }

    return $false
}

function Add-AdAceIfMissing {
    param(
        [Parameter(Mandatory = $true)][string]$Server,
        [Parameter(Mandatory = $true)][string]$TargetDn,
        [Parameter(Mandatory = $true)][System.Security.Principal.SecurityIdentifier]$PrincipalSid,
        [Parameter(Mandatory = $true)][System.DirectoryServices.ActiveDirectoryRights]$Rights,
        [Guid]$ObjectType = [Guid]::Empty,
        [Parameter(Mandatory = $true)][string]$Description
    )

    $entry = Get-DirectoryEntry -Server $Server -DistinguishedName $TargetDn
    try {
        $acl = $entry.ObjectSecurity
        if (Test-AceExists -Acl $acl -Sid $PrincipalSid -Rights $Rights -ObjectType $ObjectType) {
            Write-Log ("ACE already present: {0}" -f $Description)
            return
        }

        if ($ObjectType -eq [Guid]::Empty) {
            $rule = New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
                $PrincipalSid,
                $Rights,
                [System.Security.AccessControl.AccessControlType]::Allow
            )
        }
        else {
            $rule = New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
                $PrincipalSid,
                $Rights,
                [System.Security.AccessControl.AccessControlType]::Allow,
                $ObjectType
            )
        }

        $acl.AddAccessRule($rule)
        $entry.ObjectSecurity = $acl
        $entry.CommitChanges()
        Write-Log ("Added ACE: {0}" -f $Description)
    }
    finally {
        $entry.Dispose()
    }
}

try {
    New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
    Write-Log 'Starting vulnerable ACL path provisioning'

    Import-Module ActiveDirectory -ErrorAction Stop

    $genericWrite = [System.DirectoryServices.ActiveDirectoryRights]::GenericWrite
    $writeDacl = [System.DirectoryServices.ActiveDirectoryRights]::WriteDacl
    $extendedRight = [System.DirectoryServices.ActiveDirectoryRights]::ExtendedRight
    $forceChangePasswordGuid = [Guid]'00299570-246d-11d0-a768-00aa006e0529'
    $authenticatedUsersSid = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-11')
    $ouNames = @('IT', 'Finance', 'HR', 'ServiceAccounts')

    foreach ($domain in $Domains) {
        Write-Log ("Processing HR-to-Finance ACL path for {0}" -f $domain)
        $domainInfo = Get-ADDomain -Server $domain
        $domainDn = $domainInfo.DistinguishedName
        $ouDns = @{}
        foreach ($ouName in $ouNames) {
            $ouDns[$ouName] = Ensure-LabOu -Name $ouName -DomainDn $domainDn -Server $domain
        }

        $hrOuDn = $ouDns['HR']
        $financeOuDn = $ouDns['Finance']
        $hrGroup = Ensure-LabGroup -Name 'HR' -Path $hrOuDn -Server $domain

        Add-AdAceIfMissing `
            -Server $domain `
            -TargetDn $financeOuDn `
            -PrincipalSid $hrGroup.SID `
            -Rights $genericWrite `
            -Description ("HR GenericWrite over Finance OU in {0}" -f $domain)
    }

    Write-Log ("Processing primary-domain ACL paths for {0}" -f $PrimaryDomain)
    $primaryInfo = Get-ADDomain -Server $PrimaryDomain
    $primaryDn = $primaryInfo.DistinguishedName
    $primaryOuDns = @{}
    foreach ($ouName in $ouNames) {
        $primaryOuDns[$ouName] = Ensure-LabOu -Name $ouName -DomainDn $primaryDn -Server $PrimaryDomain
    }

    $serviceOuDn = $primaryOuDns['ServiceAccounts']
    $serviceGroup = Ensure-LabGroup -Name 'ServiceAccounts' -Path $serviceOuDn -Server $PrimaryDomain
    $tywin = Get-RequiredUser -SamAccountName 'tywin.lannister' -Server $PrimaryDomain
    $sansa = Get-RequiredUser -SamAccountName 'sansa.stark' -Server $PrimaryDomain

    Add-AdAceIfMissing `
        -Server $PrimaryDomain `
        -TargetDn $tywin.DistinguishedName `
        -PrincipalSid $serviceGroup.SID `
        -Rights $writeDacl `
        -Description 'ServiceAccounts WriteDACL over tywin.lannister'

    Add-AdAceIfMissing `
        -Server $PrimaryDomain `
        -TargetDn $sansa.DistinguishedName `
        -PrincipalSid $authenticatedUsersSid `
        -Rights $extendedRight `
        -ObjectType $forceChangePasswordGuid `
        -Description 'Authenticated Users ForceChangePassword over sansa.stark'

    Write-Log 'Vulnerable ACL path provisioning completed successfully'
}
catch {
    $message = 'Vulnerable ACL path provisioning failed: {0}' -f $_.Exception.Message
    Write-Log $message 'ERROR'
    if ($_.ScriptStackTrace) {
        Write-Log $_.ScriptStackTrace 'ERROR'
    }
    throw
}
