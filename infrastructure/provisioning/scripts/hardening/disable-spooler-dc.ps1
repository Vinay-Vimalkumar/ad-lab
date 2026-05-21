#requires -version 5.1
<#
Purpose: Disable the Print Spooler service on domain controllers.
Prerequisites: Run as Administrator on DCs or pass -Force on a lab member host.
Expected runtime: Under 1 minute per host.
What it changes: Stops Spooler and sets startup type to Disabled.
Rollback procedure: Set Spooler startup type to Automatic and start the service.
#>
[CmdletBinding()]
param([switch]$Force)

$ErrorActionPreference = 'Stop'
$LogRoot = 'C:\LabProvisioning\logs'
$LogPath = Join-Path $LogRoot ("disable-spooler-dc-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Add-Content -Path $LogPath -Value $line
    Write-Output $line
}

try {
    New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
    $role = (Get-CimInstance Win32_ComputerSystem).DomainRole
    if (-not $Force -and $role -lt 4) {
        Write-Log 'Host is not a domain controller; skipping. Use -Force to override.' 'WARN'
        return
    }
    Stop-Service -Name Spooler -Force -ErrorAction SilentlyContinue
    Set-Service -Name Spooler -StartupType Disabled
    Write-Log 'Print Spooler disabled.'
} catch {
    Write-Log $_.Exception.Message 'ERROR'
    throw
}
