#requires -version 5.1
<#
Purpose: Disable LLMNR and NetBIOS name resolution to reduce NTLM capture and relay.
Prerequisites: Run locally as Administrator; validate DNS records for short-name dependencies.
Expected runtime: Under 1 minute per host.
What it changes: Sets EnableMulticast=0 and per-adapter TcpipNetbiosOptions=2.
Rollback procedure: Set EnableMulticast=1 and adapter TcpipNetbiosOptions to 0 or the prior value.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$LogRoot = 'C:\LabProvisioning\logs'
$LogPath = Join-Path $LogRoot ("disable-llmnr-nbtns-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Add-Content -Path $LogPath -Value $line
    Write-Output $line
}

try {
    New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
    New-Item -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient' -Force | Out-Null
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient' -Name EnableMulticast -Type DWord -Value 0
    Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters\Interfaces' -ErrorAction SilentlyContinue |
        ForEach-Object { Set-ItemProperty -Path $_.PSPath -Name NetbiosOptions -Type DWord -Value 2 }
    Write-Log 'Disabled LLMNR and NBT-NS settings.'
} catch {
    Write-Log $_.Exception.Message 'ERROR'
    throw
}
