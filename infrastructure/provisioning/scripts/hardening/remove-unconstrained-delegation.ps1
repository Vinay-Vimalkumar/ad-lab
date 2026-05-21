#requires -version 5.1
<#
Purpose: Remove unconstrained delegation from non-DC lab principals.
Prerequisites: Run with ActiveDirectory module and Domain Admin rights.
Expected runtime: Under 1 minute per domain.
What it changes: Clears TRUSTED_FOR_DELEGATION from non-DC users/computers and marks privileged users non-delegable.
Rollback procedure: Re-enable TrustedForDelegation only for documented service accounts that truly require it.
#>
[CmdletBinding()]
param([string[]]$Domains = @('sevenkingdoms.local', 'north.sevenkingdoms.local'))

$ErrorActionPreference = 'Stop'
$LogRoot = 'C:\LabProvisioning\logs'
$LogPath = Join-Path $LogRoot ("remove-unconstrained-delegation-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))

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
        $objects = Get-ADObject -LDAPFilter '(userAccountControl:1.2.840.113556.1.4.803:=524288)' -Server $domain -Properties userAccountControl,primaryGroupID
        foreach ($object in $objects) {
            if ($object.ObjectClass -eq 'computer' -and $object.primaryGroupID -eq 516) {
                Write-Log "Skipping DC $($object.Name) in $domain."
                continue
            }
            Set-ADAccountControl -Identity $object.DistinguishedName -Server $domain -TrustedForDelegation $false
            Write-Log "Removed unconstrained delegation from $($object.Name) in $domain."
        }
        Get-ADUser -LDAPFilter '(adminCount=1)' -Server $domain | ForEach-Object {
            Set-ADAccountControl -Identity $_.DistinguishedName -Server $domain -AccountNotDelegated $true
        }
    }
} catch {
    Write-Log $_.Exception.Message 'ERROR'
    throw
}
