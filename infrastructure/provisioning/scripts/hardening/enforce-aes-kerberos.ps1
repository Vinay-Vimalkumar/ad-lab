#requires -version 5.1
<#
Purpose: Configure service accounts to support AES Kerberos encryption and avoid RC4.
Prerequisites: Run with ActiveDirectory module and coordinate service-account password rotation.
Expected runtime: Under 1 minute per domain.
What it changes: Sets msDS-SupportedEncryptionTypes to AES128+AES256 for service accounts.
Rollback procedure: Restore prior msDS-SupportedEncryptionTypes values if a legacy service breaks.
#>
[CmdletBinding()]
param([string[]]$Domains = @('sevenkingdoms.local', 'north.sevenkingdoms.local'))

$ErrorActionPreference = 'Stop'
$LogRoot = 'C:\LabProvisioning\logs'
$LogPath = Join-Path $LogRoot ("enforce-aes-kerberos-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Add-Content -Path $LogPath -Value $line
    Write-Output $line
}

try {
    New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
    Import-Module ActiveDirectory -ErrorAction Stop
    foreach ($domain in $Domains) {
        Get-ADUser -LDAPFilter '(servicePrincipalName=*)' -Server $domain -Properties servicePrincipalName |
            ForEach-Object {
                Set-ADUser -Identity $_.DistinguishedName -Server $domain -Replace @{ 'msDS-SupportedEncryptionTypes' = 24 }
                Write-Log "Set AES-only Kerberos flags on $($_.SamAccountName) in $domain."
            }
    }
} catch {
    Write-Log $_.Exception.Message 'ERROR'
    throw
}
