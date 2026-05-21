#requires -version 5.1
<#
Purpose: Remove the dangerous ACLs intentionally seeded in the lab.
Prerequisites: Run with ActiveDirectory module, Domain Admin rights, and an ACL backup.
Expected runtime: 1-2 minutes in the lab.
What it changes: Removes matching HR GenericWrite, ServiceAccounts WriteDACL, and Authenticated Users ForceChangePassword ACEs.
Rollback procedure: Re-run create-acl-paths.ps1 to restore the vulnerable lab state.
#>
[CmdletBinding()]
param(
    [string[]]$Domains = @('sevenkingdoms.local', 'north.sevenkingdoms.local'),
    [string]$PrimaryDomain = 'sevenkingdoms.local'
)

$ErrorActionPreference = 'Stop'
$LogRoot = 'C:\LabProvisioning\logs'
$LogPath = Join-Path $LogRoot ("remediate-dangerous-acls-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Add-Content -Path $LogPath -Value $line
    Write-Output $line
}

function Remove-MatchingAce {
    param(
        [string]$Server,
        [string]$TargetDn,
        [System.Security.Principal.SecurityIdentifier]$Sid,
        [System.DirectoryServices.ActiveDirectoryRights]$Rights,
        [Guid]$ObjectType = [Guid]::Empty
    )

    $entry = New-Object System.DirectoryServices.DirectoryEntry("LDAP://$Server/$TargetDn")
    $acl = $entry.ObjectSecurity
    $rules = $acl.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier])
    foreach ($rule in $rules) {
        if ($rule.IdentityReference.Value -eq $Sid.Value -and (($rule.ActiveDirectoryRights -band $Rights) -eq $Rights) -and ($ObjectType -eq [Guid]::Empty -or $rule.ObjectType -eq $ObjectType)) {
            [void]$acl.RemoveAccessRule($rule)
        }
    }
    $entry.ObjectSecurity = $acl
    $entry.CommitChanges()
}

try {
    New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
    Import-Module ActiveDirectory -ErrorAction Stop
    $forceChangePasswordGuid = [Guid]'00299570-246d-11d0-a768-00aa006e0529'
    foreach ($domain in $Domains) {
        $domainInfo = Get-ADDomain -Server $domain
        $hr = Get-ADGroup -Identity 'HR' -Server $domain -Properties objectSid
        Remove-MatchingAce -Server $domain -TargetDn ("OU=Finance,{0}" -f $domainInfo.DistinguishedName) -Sid $hr.SID -Rights ([System.DirectoryServices.ActiveDirectoryRights]::GenericWrite)
        Write-Log "Removed HR GenericWrite over Finance in $domain."
    }
    $serviceGroup = Get-ADGroup -Identity 'ServiceAccounts' -Server $PrimaryDomain -Properties objectSid
    $tywin = Get-ADUser -Identity 'tywin.lannister' -Server $PrimaryDomain
    $sansa = Get-ADUser -Identity 'sansa.stark' -Server $PrimaryDomain
    $authenticatedUsers = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-11')
    Remove-MatchingAce -Server $PrimaryDomain -TargetDn $tywin.DistinguishedName -Sid $serviceGroup.SID -Rights ([System.DirectoryServices.ActiveDirectoryRights]::WriteDacl)
    Remove-MatchingAce -Server $PrimaryDomain -TargetDn $sansa.DistinguishedName -Sid $authenticatedUsers -Rights ([System.DirectoryServices.ActiveDirectoryRights]::ExtendedRight) -ObjectType $forceChangePasswordGuid
    Write-Log 'Removed ServiceAccounts WriteDACL and Authenticated Users ForceChangePassword paths.'
} catch {
    Write-Log $_.Exception.Message 'ERROR'
    throw
}
