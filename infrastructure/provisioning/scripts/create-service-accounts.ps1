#requires -version 5.1
<#
.SYNOPSIS
Creates Kerberoastable service accounts and their SPNs for the AD lab.

.IDEMPOTENCY
This script creates the ServiceAccounts OU and ServiceAccounts security group
when missing, creates missing service accounts, enables existing accounts,
preserves existing passwords unless -ResetExistingPasswords is supplied, and
adds only missing SPN values. If a requested SPN already belongs to a different
object, the script stops with an informative error instead of reassigning it.
All secrets are lab placeholders only.
#>
[CmdletBinding()]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', 'LabPassword', Justification = 'AD lab bootstrap uses a placeholder value only; real secrets must come from the environment.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '', Justification = 'AD cmdlets require SecureString and the input is an explicit lab placeholder.')]
param(
    [ValidateNotNullOrEmpty()]
    [string[]]$Domains = @('sevenkingdoms.local', 'north.sevenkingdoms.local'),

    [ValidateNotNullOrEmpty()]
    [string]$LabPassword = 'Lab-Placeholder-Password1!',

    [switch]$ResetExistingPasswords
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$LogRoot = 'C:\LabProvisioning\logs'
$LogPath = Join-Path $LogRoot ("create-service-accounts-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))

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
    else {
        Write-Log ("OU {0} already exists in {1}" -f $Name, $Server)
    }

    return $ouDn
}

function Ensure-ServiceAccountsGroup {
    param(
        [Parameter(Mandatory = $true)][string]$OuDn,
        [Parameter(Mandatory = $true)][string]$Server
    )

    $group = Get-ADGroup -LDAPFilter '(sAMAccountName=ServiceAccounts)' -Server $Server -ErrorAction SilentlyContinue
    if ($null -eq $group) {
        $group = New-ADGroup -Name 'ServiceAccounts' -SamAccountName 'ServiceAccounts' -GroupCategory Security -GroupScope Global -Path $OuDn -Server $Server -PassThru
        Write-Log ("Created ServiceAccounts group in {0}" -f $Server)
    }
    else {
        Write-Log ("ServiceAccounts group already exists in {0}" -f $Server)
    }

    return $group
}

function Get-AccountBySam {
    param(
        [Parameter(Mandatory = $true)][string]$SamAccountName,
        [Parameter(Mandatory = $true)][string]$Server
    )

    $escapedSam = Escape-LdapFilterValue -Value $SamAccountName
    return Get-ADUser -LDAPFilter "(sAMAccountName=$escapedSam)" -Server $Server -Properties ServicePrincipalName,PasswordNeverExpires,UserPrincipalName -ErrorAction SilentlyContinue
}

function Ensure-GroupMember {
    param(
        [Parameter(Mandatory = $true)][string]$GroupDn,
        [Parameter(Mandatory = $true)][string]$MemberDn,
        [Parameter(Mandatory = $true)][string]$Server
    )

    $group = Get-ADGroup -Identity $GroupDn -Server $Server -Properties member
    if (@($group.member) -notcontains $MemberDn) {
        $directoryGroup = [ADSI]("LDAP://{0}" -f $GroupDn)
        $directoryGroup.Add("LDAP://{0}" -f $MemberDn)
        $directoryGroup.CommitChanges()
        Write-Log ("Added {0} to ServiceAccounts in {1}" -f $MemberDn, $Server)
    }
    else {
        Write-Log ("{0} is already in ServiceAccounts in {1}" -f $MemberDn, $Server)
    }
}

function Ensure-Spn {
    param(
        [Parameter(Mandatory = $true)][string]$Spn,
        [Parameter(Mandatory = $true)]$Account,
        [Parameter(Mandatory = $true)][string]$Server
    )

    $escapedSpn = Escape-LdapFilterValue -Value $Spn
    $owner = Get-ADObject -LDAPFilter "(servicePrincipalName=$escapedSpn)" -Server $Server -Properties servicePrincipalName,sAMAccountName -ErrorAction SilentlyContinue

    if ($null -ne $owner -and $owner.DistinguishedName -ne $Account.DistinguishedName) {
        throw "SPN $Spn is already assigned to $($owner.DistinguishedName) in $Server."
    }

    if (@($Account.ServicePrincipalName) -notcontains $Spn) {
        Set-ADUser -Identity $Account.DistinguishedName -ServicePrincipalNames @{ Add = $Spn } -Server $Server
        Write-Log ("Added SPN {0} to {1} in {2}" -f $Spn, $Account.SamAccountName, $Server)
    }
    else {
        Write-Log ("SPN {0} already present on {1} in {2}" -f $Spn, $Account.SamAccountName, $Server)
    }
}

function Ensure-ServiceAccount {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Spec,
        [Parameter(Mandatory = $true)][string]$OuDn,
        [Parameter(Mandatory = $true)][string]$ServiceGroupDn,
        [Parameter(Mandatory = $true)][string]$Server,
        [Parameter(Mandatory = $true)][securestring]$SecurePassword,
        [Parameter(Mandatory = $true)][bool]$ResetPassword
    )

    $sam = $Spec.Sam
    $upn = '{0}@{1}' -f $sam, $Spec.Domain
    $account = Get-AccountBySam -SamAccountName $sam -Server $Server

    if ($null -eq $account) {
        New-ADUser `
            -Name $sam `
            -SamAccountName $sam `
            -UserPrincipalName $upn `
            -DisplayName $Spec.DisplayName `
            -Description $Spec.Description `
            -Path $OuDn `
            -AccountPassword $SecurePassword `
            -Enabled $true `
            -ChangePasswordAtLogon $false `
            -PasswordNeverExpires $true `
            -Server $Server | Out-Null
        Write-Log ("Created service account {0} in {1}" -f $sam, $Server)
        $account = Get-AccountBySam -SamAccountName $sam -Server $Server
    }
    else {
        Set-ADUser `
            -Identity $account.DistinguishedName `
            -UserPrincipalName $upn `
            -DisplayName $Spec.DisplayName `
            -Description $Spec.Description `
            -PasswordNeverExpires $true `
            -Server $Server
        Enable-ADAccount -Identity $account.DistinguishedName -Server $Server

        $currentParent = $account.DistinguishedName.Substring($account.DistinguishedName.IndexOf(',') + 1)
        if ($currentParent -ne $OuDn) {
            Move-ADObject -Identity $account.DistinguishedName -TargetPath $OuDn -Server $Server
            Write-Log ("Moved service account {0} to {1}" -f $sam, $OuDn)
            $account = Get-AccountBySam -SamAccountName $sam -Server $Server
        }

        if ($ResetPassword) {
            Set-ADAccountPassword -Identity $account.DistinguishedName -NewPassword $SecurePassword -Reset -Server $Server
            Write-Log ("Reset placeholder password for existing service account {0}" -f $sam)
        }
        else {
            Write-Log ("Updated existing service account {0}; password left unchanged" -f $sam)
        }

        $account = Get-AccountBySam -SamAccountName $sam -Server $Server
    }

    Set-ADUser -Identity $account.DistinguishedName -KerberosEncryptionType RC4 -Server $Server
    Ensure-GroupMember -GroupDn $ServiceGroupDn -MemberDn $account.DistinguishedName -Server $Server

    foreach ($spn in $Spec.Spns) {
        $account = Get-AccountBySam -SamAccountName $sam -Server $Server
        Ensure-Spn -Spn $spn -Account $account -Server $Server
    }
}

try {
    New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
    Write-Log 'Starting service account provisioning'

    Import-Module ActiveDirectory -ErrorAction Stop

    if ($env:LAB_PLACEHOLDER_PASSWORD) {
        $LabPassword = $env:LAB_PLACEHOLDER_PASSWORD
        Write-Log 'Using LAB_PLACEHOLDER_PASSWORD environment value'
    }
    else {
        Write-Log 'Using built-in lab placeholder password value' 'WARN'
    }

    $securePassword = ConvertTo-SecureString $LabPassword -AsPlainText -Force
    $ouNames = @('IT', 'Finance', 'HR', 'ServiceAccounts')

    $serviceAccounts = @(
        @{
            Domain = 'sevenkingdoms.local'
            Sam = 'svc_mssql'
            DisplayName = 'SQL Server Service'
            Description = 'LAB PLACEHOLDER: Kerberoastable MSSQL service account'
            Spns = @('MSSQLSvc/sql01.sevenkingdoms.local:1433')
        },
        @{
            Domain = 'sevenkingdoms.local'
            Sam = 'svc_web'
            DisplayName = 'Web Application Service'
            Description = 'LAB PLACEHOLDER: Kerberoastable HTTP service account'
            Spns = @('HTTP/web01.sevenkingdoms.local')
        },
        @{
            Domain = 'sevenkingdoms.local'
            Sam = 'svc_cifs'
            DisplayName = 'File Server Service'
            Description = 'LAB PLACEHOLDER: Kerberoastable CIFS service account'
            Spns = @('CIFS/fileserver.sevenkingdoms.local')
        },
        @{
            Domain = 'north.sevenkingdoms.local'
            Sam = 'svc_ldap'
            DisplayName = 'LDAP Application Service'
            Description = 'LAB PLACEHOLDER: Kerberoastable LDAP service account'
            Spns = @('LDAP/app01.north.sevenkingdoms.local')
        }
    )

    foreach ($domain in $Domains) {
        Write-Log ("Processing domain {0}" -f $domain)
        $domainInfo = Get-ADDomain -Server $domain
        $ouDns = @{}
        foreach ($ouName in $ouNames) {
            $ouDns[$ouName] = Ensure-LabOu -Name $ouName -DomainDn $domainInfo.DistinguishedName -Server $domain
        }

        $serviceOuDn = $ouDns['ServiceAccounts']
        $serviceGroup = Ensure-ServiceAccountsGroup -OuDn $serviceOuDn -Server $domain

        foreach ($accountSpec in $serviceAccounts | Where-Object { $_.Domain -ieq $domain }) {
            Ensure-ServiceAccount -Spec $accountSpec -OuDn $serviceOuDn -ServiceGroupDn $serviceGroup.DistinguishedName -Server $domain -SecurePassword $securePassword -ResetPassword:$ResetExistingPasswords.IsPresent
        }
    }

    Write-Log 'Service account provisioning completed successfully'
}
catch {
    $message = 'Service account provisioning failed: {0}' -f $_.Exception.Message
    Write-Log $message 'ERROR'
    if ($_.ScriptStackTrace) {
        Write-Log $_.ScriptStackTrace 'ERROR'
    }
    throw
}
