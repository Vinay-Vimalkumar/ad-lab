#requires -version 5.1
<#
.SYNOPSIS
Creates Game of Thrones-themed AD lab users and departmental OUs/groups.

.IDEMPOTENCY
This script converges the lab directory without deleting existing objects. It
creates the IT, Finance, HR, and ServiceAccounts OUs when missing, creates
department security groups when missing, creates missing users, updates safe
profile attributes on existing users, moves users into their expected OUs, and
adds missing direct group memberships. Existing passwords are not reset unless
-ResetExistingPasswords is provided. All secrets are lab placeholders only.
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
$LogPath = Join-Path $LogRoot ("create-users-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))

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
    try {
        $ou = Get-ADOrganizationalUnit -Identity $ouDn -Server $Server -ErrorAction Stop
    }
    catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {
        $ou = $null
    }

    if ($null -eq $ou) {
        New-ADOrganizationalUnit -Name $Name -Path $DomainDn -Server $Server -ProtectedFromAccidentalDeletion $false | Out-Null
        Write-Log ("Created OU {0} in {1}" -f $Name, $Server)
    }
    else {
        Write-Log ("OU {0} already exists in {1}" -f $Name, $Server)
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
    $group = Get-ADGroup -LDAPFilter "(sAMAccountName=$escapedName)" -Server $Server -ErrorAction SilentlyContinue
    if ($null -eq $group) {
        $group = New-ADGroup -Name $Name -SamAccountName $Name -GroupCategory Security -GroupScope Global -Path $Path -Server $Server -PassThru
        Write-Log ("Created security group {0} in {1}" -f $Name, $Server)
    }
    else {
        Write-Log ("Security group {0} already exists in {1}" -f $Name, $Server)
    }

    return $group
}

function Ensure-GroupMember {
    param(
        [Parameter(Mandatory = $true)][string]$GroupIdentity,
        [Parameter(Mandatory = $true)][string]$MemberDn,
        [Parameter(Mandatory = $true)][string]$Server
    )

    $group = Get-ADGroup -Identity $GroupIdentity -Server $Server -Properties member
    $members = @($group.member)
    if ($members -notcontains $MemberDn) {
        $directoryGroup = [ADSI]("LDAP://{0}" -f $group.DistinguishedName)
        $directoryGroup.Add("LDAP://{0}" -f $MemberDn)
        $directoryGroup.CommitChanges()
        Write-Log ("Added {0} to {1} in {2}" -f $MemberDn, $group.Name, $Server)
    }
    else {
        Write-Log ("{0} is already a direct member of {1} in {2}" -f $MemberDn, $group.Name, $Server)
    }
}

function Get-UserBySam {
    param(
        [Parameter(Mandatory = $true)][string]$SamAccountName,
        [Parameter(Mandatory = $true)][string]$Server
    )

    $escapedSam = Escape-LdapFilterValue -Value $SamAccountName
    return Get-ADUser -LDAPFilter "(sAMAccountName=$escapedSam)" -Server $Server -Properties Department,Title,UserPrincipalName,DisplayName,PasswordNeverExpires -ErrorAction SilentlyContinue
}

function Ensure-LabUser {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Spec,
        [Parameter(Mandatory = $true)][string]$OuDn,
        [Parameter(Mandatory = $true)][string]$Server,
        [Parameter(Mandatory = $true)][securestring]$SecurePassword,
        [Parameter(Mandatory = $true)][bool]$ResetPassword
    )

    $sam = $Spec.Sam
    $displayName = '{0} {1}' -f $Spec.GivenName, $Spec.Surname
    $upn = '{0}@{1}' -f $sam, $Spec.Domain
    $user = Get-UserBySam -SamAccountName $sam -Server $Server

    if ($null -eq $user) {
        New-ADUser `
            -Name $displayName `
            -SamAccountName $sam `
            -UserPrincipalName $upn `
            -GivenName $Spec.GivenName `
            -Surname $Spec.Surname `
            -DisplayName $displayName `
            -Department $Spec.Department `
            -Title $Spec.Title `
            -Path $OuDn `
            -AccountPassword $SecurePassword `
            -Enabled $true `
            -ChangePasswordAtLogon $false `
            -PasswordNeverExpires $true `
            -Server $Server | Out-Null
        Write-Log ("Created user {0} in {1}" -f $sam, $Server)
        $user = Get-UserBySam -SamAccountName $sam -Server $Server
    }
    else {
        Set-ADUser `
            -Identity $user.DistinguishedName `
            -UserPrincipalName $upn `
            -GivenName $Spec.GivenName `
            -Surname $Spec.Surname `
            -DisplayName $displayName `
            -Department $Spec.Department `
            -Title $Spec.Title `
            -PasswordNeverExpires $true `
            -Server $Server

        Enable-ADAccount -Identity $user.DistinguishedName -Server $Server

        $currentParent = $user.DistinguishedName.Substring($user.DistinguishedName.IndexOf(',') + 1)
        if ($currentParent -ne $OuDn) {
            Move-ADObject -Identity $user.DistinguishedName -TargetPath $OuDn -Server $Server
            Write-Log ("Moved user {0} to {1}" -f $sam, $OuDn)
            $user = Get-UserBySam -SamAccountName $sam -Server $Server
        }

        if ($ResetPassword) {
            Set-ADAccountPassword -Identity $user.DistinguishedName -NewPassword $SecurePassword -Reset -Server $Server
            Write-Log ("Reset placeholder password for existing user {0}" -f $sam)
        }
        else {
            Write-Log ("Updated existing user {0}; password left unchanged" -f $sam)
        }
    }

    Ensure-GroupMember -GroupIdentity $Spec.Department -MemberDn $user.DistinguishedName -Server $Server
    return $user
}

try {
    New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
    Write-Log 'Starting user provisioning'

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
    $departmentGroups = @('IT', 'Finance', 'HR')

    $users = @(
        @{ Domain = 'sevenkingdoms.local'; Sam = 'jon.snow'; GivenName = 'Jon'; Surname = 'Snow'; Department = 'IT'; Title = 'Night Watch Analyst' },
        @{ Domain = 'sevenkingdoms.local'; Sam = 'arya.stark'; GivenName = 'Arya'; Surname = 'Stark'; Department = 'IT'; Title = 'Endpoint Operator' },
        @{ Domain = 'sevenkingdoms.local'; Sam = 'sansa.stark'; GivenName = 'Sansa'; Surname = 'Stark'; Department = 'HR'; Title = 'HR Coordinator' },
        @{ Domain = 'sevenkingdoms.local'; Sam = 'cersei.lannister'; GivenName = 'Cersei'; Surname = 'Lannister'; Department = 'Finance'; Title = 'Finance Director' },
        @{ Domain = 'sevenkingdoms.local'; Sam = 'tywin.lannister'; GivenName = 'Tywin'; Surname = 'Lannister'; Department = 'Finance'; Title = 'Domain Administrator' },
        @{ Domain = 'sevenkingdoms.local'; Sam = 'jaime.lannister'; GivenName = 'Jaime'; Surname = 'Lannister'; Department = 'Finance'; Title = 'Treasury Analyst' },
        @{ Domain = 'sevenkingdoms.local'; Sam = 'tyrion.lannister'; GivenName = 'Tyrion'; Surname = 'Lannister'; Department = 'IT'; Title = 'Systems Strategist' },
        @{ Domain = 'sevenkingdoms.local'; Sam = 'daenerys.targaryen'; GivenName = 'Daenerys'; Surname = 'Targaryen'; Department = 'IT'; Title = 'Cloud Platform Lead' },
        @{ Domain = 'sevenkingdoms.local'; Sam = 'jorah.mormont'; GivenName = 'Jorah'; Surname = 'Mormont'; Department = 'HR'; Title = 'People Operations Advisor' },
        @{ Domain = 'sevenkingdoms.local'; Sam = 'varys.spider'; GivenName = 'Varys'; Surname = 'Spider'; Department = 'IT'; Title = 'Identity Intelligence Analyst' },
        @{ Domain = 'sevenkingdoms.local'; Sam = 'petyr.baelish'; GivenName = 'Petyr'; Surname = 'Baelish'; Department = 'Finance'; Title = 'Risk Manager' },
        @{ Domain = 'sevenkingdoms.local'; Sam = 'brienne.tarth'; GivenName = 'Brienne'; Surname = 'Tarth'; Department = 'HR'; Title = 'Employee Relations Lead' },
        @{ Domain = 'sevenkingdoms.local'; Sam = 'sandor.clegane'; GivenName = 'Sandor'; Surname = 'Clegane'; Department = 'IT'; Title = 'Server Operations Engineer' },
        @{ Domain = 'sevenkingdoms.local'; Sam = 'gregor.clegane'; GivenName = 'Gregor'; Surname = 'Clegane'; Department = 'IT'; Title = 'Datacenter Technician' },
        @{ Domain = 'sevenkingdoms.local'; Sam = 'margaery.tyrell'; GivenName = 'Margaery'; Surname = 'Tyrell'; Department = 'HR'; Title = 'Talent Partner' },
        @{ Domain = 'sevenkingdoms.local'; Sam = 'olenna.tyrell'; GivenName = 'Olenna'; Surname = 'Tyrell'; Department = 'Finance'; Title = 'Audit Advisor' },
        @{ Domain = 'sevenkingdoms.local'; Sam = 'davos.seaworth'; GivenName = 'Davos'; Surname = 'Seaworth'; Department = 'IT'; Title = 'Network Engineer' },
        @{ Domain = 'sevenkingdoms.local'; Sam = 'stannis.baratheon'; GivenName = 'Stannis'; Surname = 'Baratheon'; Department = 'Finance'; Title = 'Compliance Officer' },
        @{ Domain = 'sevenkingdoms.local'; Sam = 'robert.baratheon'; GivenName = 'Robert'; Surname = 'Baratheon'; Department = 'Finance'; Title = 'Budget Owner' },
        @{ Domain = 'sevenkingdoms.local'; Sam = 'renly.baratheon'; GivenName = 'Renly'; Surname = 'Baratheon'; Department = 'HR'; Title = 'Benefits Specialist' },
        @{ Domain = 'sevenkingdoms.local'; Sam = 'theon.greyjoy'; GivenName = 'Theon'; Surname = 'Greyjoy'; Department = 'IT'; Title = 'Helpdesk Technician' },
        @{ Domain = 'sevenkingdoms.local'; Sam = 'yara.greyjoy'; GivenName = 'Yara'; Surname = 'Greyjoy'; Department = 'IT'; Title = 'Security Operations Lead' },
        @{ Domain = 'sevenkingdoms.local'; Sam = 'melisandre.red'; GivenName = 'Melisandre'; Surname = 'Red'; Department = 'HR'; Title = 'Workforce Planner' },
        @{ Domain = 'sevenkingdoms.local'; Sam = 'missandei.naath'; GivenName = 'Missandei'; Surname = 'Naath'; Department = 'HR'; Title = 'Communications Specialist' },
        @{ Domain = 'sevenkingdoms.local'; Sam = 'grey.worm'; GivenName = 'Grey'; Surname = 'Worm'; Department = 'IT'; Title = 'Access Control Engineer' },
        @{ Domain = 'sevenkingdoms.local'; Sam = 'bronn.blackwater'; GivenName = 'Bronn'; Surname = 'Blackwater'; Department = 'Finance'; Title = 'Accounts Payable Analyst' },
        @{ Domain = 'north.sevenkingdoms.local'; Sam = 'eddard.stark'; GivenName = 'Eddard'; Surname = 'Stark'; Department = 'IT'; Title = 'Domain Administrator' },
        @{ Domain = 'north.sevenkingdoms.local'; Sam = 'brandon.stark'; GivenName = 'Brandon'; Surname = 'Stark'; Department = 'IT'; Title = 'Directory Services Analyst' },
        @{ Domain = 'north.sevenkingdoms.local'; Sam = 'catelyn.stark'; GivenName = 'Catelyn'; Surname = 'Stark'; Department = 'HR'; Title = 'HR Manager' },
        @{ Domain = 'north.sevenkingdoms.local'; Sam = 'robb.stark'; GivenName = 'Robb'; Surname = 'Stark'; Department = 'IT'; Title = 'Infrastructure Lead' },
        @{ Domain = 'north.sevenkingdoms.local'; Sam = 'rickon.stark'; GivenName = 'Rickon'; Surname = 'Stark'; Department = 'HR'; Title = 'Recruiting Coordinator' },
        @{ Domain = 'north.sevenkingdoms.local'; Sam = 'lyanna.mormont'; GivenName = 'Lyanna'; Surname = 'Mormont'; Department = 'HR'; Title = 'People Operations Lead' },
        @{ Domain = 'north.sevenkingdoms.local'; Sam = 'tormund.giantsbane'; GivenName = 'Tormund'; Surname = 'Giantsbane'; Department = 'IT'; Title = 'Field Services Engineer' },
        @{ Domain = 'north.sevenkingdoms.local'; Sam = 'jeor.mormont'; GivenName = 'Jeor'; Surname = 'Mormont'; Department = 'IT'; Title = 'Operations Manager' },
        @{ Domain = 'north.sevenkingdoms.local'; Sam = 'maester.aemon'; GivenName = 'Maester'; Surname = 'Aemon'; Department = 'IT'; Title = 'Knowledge Systems Analyst' }
    )

    $domainAdminUsers = @{
        'sevenkingdoms.local' = @('tywin.lannister')
        'north.sevenkingdoms.local' = @('eddard.stark')
    }

    foreach ($domain in $Domains) {
        Write-Log ("Processing domain {0}" -f $domain)
        $domainInfo = Get-ADDomain -Server $domain
        $domainDn = $domainInfo.DistinguishedName

        $ouDns = @{}
        foreach ($ouName in $ouNames) {
            $ouDns[$ouName] = Ensure-LabOu -Name $ouName -DomainDn $domainDn -Server $domain
        }

        foreach ($groupName in $departmentGroups) {
            Ensure-LabGroup -Name $groupName -Path $ouDns[$groupName] -Server $domain | Out-Null
        }

        foreach ($userSpec in $users | Where-Object { $_.Domain -ieq $domain }) {
            $ouDn = $ouDns[$userSpec.Department]
            Ensure-LabUser -Spec $userSpec -OuDn $ouDn -Server $domain -SecurePassword $securePassword -ResetPassword:$ResetExistingPasswords.IsPresent | Out-Null
        }

        if ($domainAdminUsers.ContainsKey($domain.ToLowerInvariant())) {
            foreach ($adminSam in $domainAdminUsers[$domain.ToLowerInvariant()]) {
                $admin = Get-UserBySam -SamAccountName $adminSam -Server $domain
                if ($null -eq $admin) {
                    throw "Domain Admin user $adminSam was not found in $domain after provisioning."
                }

                Ensure-GroupMember -GroupIdentity 'Domain Admins' -MemberDn $admin.DistinguishedName -Server $domain
            }
        }
    }

    Write-Log 'User provisioning completed successfully'
}
catch {
    $message = 'User provisioning failed: {0}' -f $_.Exception.Message
    Write-Log $message 'ERROR'
    if ($_.ScriptStackTrace) {
        Write-Log $_.ScriptStackTrace 'ERROR'
    }
    throw
}
