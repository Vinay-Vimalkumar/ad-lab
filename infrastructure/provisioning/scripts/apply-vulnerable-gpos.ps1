#requires -version 5.1
<#
.SYNOPSIS
Applies intentionally vulnerable GPO and AD policy settings for the lab.

.IDEMPOTENCY
This script creates or reuses named LAB-* GPOs, rewrites the same registry
policy values to the requested vulnerable state, creates missing OU/group
dependencies, and creates or updates a Finance fine-grained password policy.
Domain account password policy cannot be scoped to a user OU with a normal GPO,
so the Finance path uses a PSO for actual domain-account behavior and a
Finance-linked GPO marker for lab visibility. Existing unrelated GPO settings
are not removed.
#>
[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()]
    [string[]]$Domains = @('sevenkingdoms.local', 'north.sevenkingdoms.local')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$LogRoot = 'C:\LabProvisioning\logs'
$LogPath = Join-Path $LogRoot ("apply-vulnerable-gpos-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))

function Write-Log {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level = 'INFO'
    )

    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Add-Content -Path $LogPath -Value $line
    Write-Host $line
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

    return $ouDn
}

function Ensure-LabGroup {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Server
    )

    $group = Get-ADGroup -LDAPFilter "(sAMAccountName=$Name)" -Server $Server -ErrorAction SilentlyContinue
    if ($null -eq $group) {
        $group = New-ADGroup -Name $Name -SamAccountName $Name -GroupCategory Security -GroupScope Global -Path $Path -Server $Server -PassThru
        Write-Log ("Created security group {0} in {1}" -f $Name, $Server)
    }

    return $group
}

function Ensure-Gpo {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Domain,
        [Parameter(Mandatory = $true)][string]$Comment
    )

    $gpo = Get-GPO -Name $Name -Domain $Domain -ErrorAction SilentlyContinue
    if ($null -eq $gpo) {
        $gpo = New-GPO -Name $Name -Domain $Domain -Comment $Comment
        Write-Log ("Created GPO {0} in {1}" -f $Name, $Domain)
    }
    else {
        Write-Log ("Reusing GPO {0} in {1}" -f $Name, $Domain)
    }

    return $gpo
}

function Ensure-GPLink {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Target,
        [Parameter(Mandatory = $true)][string]$Domain
    )

    $inheritance = Get-GPInheritance -Target $Target -Domain $Domain
    $existing = @($inheritance.GpoLinks) | Where-Object { $_.DisplayName -eq $Name }
    if ($null -eq $existing -or @($existing).Count -eq 0) {
        New-GPLink -Name $Name -Target $Target -Domain $Domain -LinkEnabled Yes | Out-Null
        Write-Log ("Linked GPO {0} to {1}" -f $Name, $Target)
    }
    else {
        Set-GPLink -Name $Name -Target $Target -Domain $Domain -LinkEnabled Yes | Out-Null
        Write-Log ("GPO {0} already linked to {1}; ensured link is enabled" -f $Name, $Target)
    }
}

function Set-GpoDword {
    param(
        [Parameter(Mandatory = $true)][string]$GpoName,
        [Parameter(Mandatory = $true)][string]$Domain,
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][string]$ValueName,
        [Parameter(Mandatory = $true)][int]$Value
    )

    Set-GPRegistryValue -Name $GpoName -Domain $Domain -Key $Key -ValueName $ValueName -Type DWord -Value $Value | Out-Null
    Write-Log ("Set {0}\{1}={2} in {3}" -f $Key, $ValueName, $Value, $GpoName)
}

function Set-GpoString {
    param(
        [Parameter(Mandatory = $true)][string]$GpoName,
        [Parameter(Mandatory = $true)][string]$Domain,
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][string]$ValueName,
        [Parameter(Mandatory = $true)][string]$Value
    )

    Set-GPRegistryValue -Name $GpoName -Domain $Domain -Key $Key -ValueName $ValueName -Type String -Value $Value | Out-Null
    Write-Log ("Set {0}\{1}={2} in {3}" -f $Key, $ValueName, $Value, $GpoName)
}

function Ensure-FinanceWeakPasswordPolicy {
    param(
        [Parameter(Mandatory = $true)][string]$Domain,
        [Parameter(Mandatory = $true)][string]$FinanceOuDn,
        [Parameter(Mandatory = $true)]$FinanceGroup
    )

    $financeUsers = Get-ADUser -SearchBase $FinanceOuDn -LDAPFilter '(objectClass=user)' -Server $Domain -ErrorAction SilentlyContinue
    $financeGroupWithMembers = Get-ADGroup -Identity $FinanceGroup.DistinguishedName -Server $Domain -Properties member
    foreach ($user in @($financeUsers)) {
        if (@($financeGroupWithMembers.member) -notcontains $user.DistinguishedName) {
            $directoryGroup = [ADSI]("LDAP://{0}" -f $FinanceGroup.DistinguishedName)
            $directoryGroup.Add("LDAP://{0}" -f $user.DistinguishedName)
            $directoryGroup.CommitChanges()
            Write-Log ("Added {0} to Finance group for weak PSO targeting" -f $user.SamAccountName)
        }
    }

    $policyName = 'LAB-Finance-Weak-Password-Policy'
    try {
        $existingPolicy = Get-ADFineGrainedPasswordPolicy -Identity $policyName -Server $Domain -ErrorAction Stop
    }
    catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {
        $existingPolicy = $null
    }

    $maxAge = New-TimeSpan -Days 3650
    $minAge = New-TimeSpan -Days 0
    $lockoutDuration = New-TimeSpan -Minutes 1
    $lockoutObservationWindow = New-TimeSpan -Minutes 1

    if ($null -eq $existingPolicy) {
        New-ADFineGrainedPasswordPolicy `
            -Name $policyName `
            -Server $Domain `
            -Precedence 50 `
            -ComplexityEnabled $false `
            -MinPasswordLength 6 `
            -PasswordHistoryCount 0 `
            -ReversibleEncryptionEnabled $true `
            -MaxPasswordAge $maxAge `
            -MinPasswordAge $minAge `
            -LockoutThreshold 0 `
            -LockoutDuration $lockoutDuration `
            -LockoutObservationWindow $lockoutObservationWindow | Out-Null
        Write-Log ("Created weak Finance fine-grained password policy in {0}" -f $Domain)
    }
    else {
        Set-ADFineGrainedPasswordPolicy `
            -Identity $policyName `
            -Server $Domain `
            -Precedence 50 `
            -ComplexityEnabled $false `
            -MinPasswordLength 6 `
            -PasswordHistoryCount 0 `
            -ReversibleEncryptionEnabled $true `
            -MaxPasswordAge $maxAge `
            -MinPasswordAge $minAge `
            -LockoutThreshold 0 `
            -LockoutDuration $lockoutDuration `
            -LockoutObservationWindow $lockoutObservationWindow
        Write-Log ("Updated weak Finance fine-grained password policy in {0}" -f $Domain)
    }

    $subjects = Get-ADFineGrainedPasswordPolicySubject -Identity $policyName -Server $Domain -ErrorAction SilentlyContinue
    if (@($subjects | Select-Object -ExpandProperty DistinguishedName) -notcontains $FinanceGroup.DistinguishedName) {
        Add-ADFineGrainedPasswordPolicySubject -Identity $policyName -Subjects $FinanceGroup.DistinguishedName -Server $Domain
        Write-Log ("Applied weak Finance PSO to Finance group in {0}" -f $Domain)
    }
    else {
        Write-Log ("Weak Finance PSO already applies to Finance group in {0}" -f $Domain)
    }
}

try {
    New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
    Write-Log 'Starting vulnerable GPO provisioning'

    Import-Module ActiveDirectory -ErrorAction Stop
    Import-Module GroupPolicy -ErrorAction Stop
    $ouNames = @('IT', 'Finance', 'HR', 'ServiceAccounts')

    foreach ($domain in $Domains) {
        Write-Log ("Processing vulnerable policy settings for {0}" -f $domain)
        $domainInfo = Get-ADDomain -Server $domain
        $domainDn = $domainInfo.DistinguishedName
        $ouDns = @{}
        foreach ($ouName in $ouNames) {
            $ouDns[$ouName] = Ensure-LabOu -Name $ouName -DomainDn $domainDn -Server $domain
        }

        $financeOuDn = $ouDns['Finance']
        $financeGroup = Ensure-LabGroup -Name 'Finance' -Path $financeOuDn -Server $domain

        $domainGpoName = 'LAB-Vulnerable-Domain-Settings'
        Ensure-Gpo -Name $domainGpoName -Domain $domain -Comment 'LAB: Enables SMBv1, NTLMv1, and LLMNR for attack-path practice.' | Out-Null
        Ensure-GPLink -Name $domainGpoName -Target $domainDn -Domain $domain
        Set-GpoDword -GpoName $domainGpoName -Domain $domain -Key 'HKLM\System\CurrentControlSet\Services\LanmanServer\Parameters' -ValueName 'SMB1' -Value 1
        Set-GpoDword -GpoName $domainGpoName -Domain $domain -Key 'HKLM\System\CurrentControlSet\Services\mrxsmb10' -ValueName 'Start' -Value 2
        Set-GpoDword -GpoName $domainGpoName -Domain $domain -Key 'HKLM\System\CurrentControlSet\Control\Lsa' -ValueName 'LmCompatibilityLevel' -Value 1
        Set-GpoDword -GpoName $domainGpoName -Domain $domain -Key 'HKLM\Software\Policies\Microsoft\Windows NT\DNSClient' -ValueName 'EnableMulticast' -Value 1

        $dcGpoName = 'LAB-Vulnerable-DC-Settings'
        $domainControllersOu = 'OU=Domain Controllers,{0}' -f $domainDn
        Ensure-Gpo -Name $dcGpoName -Domain $domain -Comment 'LAB: Allows anonymous enumeration-style settings and keeps Print Spooler enabled on DCs.' | Out-Null
        Ensure-GPLink -Name $dcGpoName -Target $domainControllersOu -Domain $domain
        Set-GpoDword -GpoName $dcGpoName -Domain $domain -Key 'HKLM\System\CurrentControlSet\Control\Lsa' -ValueName 'RestrictAnonymous' -Value 0
        Set-GpoDword -GpoName $dcGpoName -Domain $domain -Key 'HKLM\System\CurrentControlSet\Control\Lsa' -ValueName 'RestrictAnonymousSAM' -Value 0
        Set-GpoDword -GpoName $dcGpoName -Domain $domain -Key 'HKLM\System\CurrentControlSet\Control\Lsa' -ValueName 'EveryoneIncludesAnonymous' -Value 1
        Set-GpoDword -GpoName $dcGpoName -Domain $domain -Key 'HKLM\System\CurrentControlSet\Services\NTDS\Parameters' -ValueName 'LDAPServerIntegrity' -Value 1
        Set-GpoDword -GpoName $dcGpoName -Domain $domain -Key 'HKLM\System\CurrentControlSet\Services\NTDS\Parameters' -ValueName 'LdapEnforceChannelBinding' -Value 0
        Set-GpoDword -GpoName $dcGpoName -Domain $domain -Key 'HKLM\System\CurrentControlSet\Services\Spooler' -ValueName 'Start' -Value 2

        $financeGpoName = 'LAB-Finance-Weak-Password-Policy'
        Ensure-Gpo -Name $financeGpoName -Domain $domain -Comment 'LAB: Marker GPO for Finance weak password policy; actual domain-account policy is the matching PSO.' | Out-Null
        Ensure-GPLink -Name $financeGpoName -Target $financeOuDn -Domain $domain
        Set-GpoString -GpoName $financeGpoName -Domain $domain -Key 'HKLM\Software\ADLab\VulnerableSettings' -ValueName 'FinancePasswordPolicy' -Value 'Weak via LAB-Finance-Weak-Password-Policy PSO'
        Ensure-FinanceWeakPasswordPolicy -Domain $domain -FinanceOuDn $financeOuDn -FinanceGroup $financeGroup
    }

    Write-Log 'Vulnerable GPO provisioning completed successfully'
}
catch {
    $message = 'Vulnerable GPO provisioning failed: {0}' -f $_.Exception.Message
    Write-Log $message 'ERROR'
    if ($_.ScriptStackTrace) {
        Write-Log $_.ScriptStackTrace 'ERROR'
    }
    throw
}
