#requires -version 5.1
<#
Purpose: Create gMSA replacements for Kerberoastable lab service accounts.
Prerequisites: Run with ActiveDirectory module, KDS root key readiness, and Domain Admin rights.
Expected runtime: 1-2 minutes in the lab.
What it changes: Creates gMSA accounts and assigns SPNs for service migration.
Rollback procedure: Stop using the gMSA on services and remove it with Remove-ADServiceAccount after validation.
#>
[CmdletBinding()]
param([string]$Domain = (Get-ADDomain).DNSRoot)

$ErrorActionPreference = 'Stop'
$LogRoot = 'C:\LabProvisioning\logs'
$LogPath = Join-Path $LogRoot ("migrate-to-gmsa-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Add-Content -Path $LogPath -Value $line
    Write-Output $line
}

try {
    New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
    Import-Module ActiveDirectory -ErrorAction Stop
    if (-not (Get-KdsRootKey -ErrorAction SilentlyContinue)) {
        Add-KdsRootKey -EffectiveTime ((Get-Date).AddHours(-10)) | Out-Null
        Write-Log 'Created lab KDS root key with backdated effective time.'
    }
    $specs = @(
        @{ Name = 'gmsa-sql'; Spn = 'MSSQLSvc/sql01.sevenkingdoms.local:1433' },
        @{ Name = 'gmsa-web'; Spn = 'HTTP/web01.sevenkingdoms.local' },
        @{ Name = 'gmsa-cifs'; Spn = 'CIFS/fileserver.sevenkingdoms.local' },
        @{ Name = 'gmsa-ldap'; Spn = 'LDAP/app01.north.sevenkingdoms.local' }
    )
    foreach ($spec in $specs) {
        if (-not (Get-ADServiceAccount -Identity $spec.Name -Server $Domain -ErrorAction SilentlyContinue)) {
            New-ADServiceAccount -Name $spec.Name -DNSHostName "$($spec.Name).$Domain" -ServicePrincipalNames $spec.Spn -Server $Domain | Out-Null
            Write-Log "Created $($spec.Name) in $Domain."
        }
    }
} catch {
    Write-Log $_.Exception.Message 'ERROR'
    throw
}
