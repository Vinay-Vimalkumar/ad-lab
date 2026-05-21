#requires -version 5.1
<#
Purpose: Restrict anonymous LDAP and SAM enumeration on domain controllers.
Prerequisites: Run as Administrator on DCs after identifying any anonymous-bind dependencies.
Expected runtime: Under 1 minute per DC.
What it changes: Sets LSA anonymous restrictions and requires LDAP server signing.
Rollback procedure: Restore RestrictAnonymous, RestrictAnonymousSAM, EveryoneIncludesAnonymous, and LDAPServerIntegrity to previous values.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$LogRoot = 'C:\LabProvisioning\logs'
$LogPath = Join-Path $LogRoot ("restrict-anonymous-ldap-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Add-Content -Path $LogPath -Value $line
    Write-Output $line
}

try {
    New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
    Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -Name RestrictAnonymous -Type DWord -Value 1
    Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -Name RestrictAnonymousSAM -Type DWord -Value 1
    Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -Name EveryoneIncludesAnonymous -Type DWord -Value 0
    New-Item -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\NTDS\Parameters' -Force | Out-Null
    Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\NTDS\Parameters' -Name LDAPServerIntegrity -Type DWord -Value 2
    Write-Log 'Anonymous LDAP and SAM enumeration restricted.'
} catch {
    Write-Log $_.Exception.Message 'ERROR'
    throw
}
