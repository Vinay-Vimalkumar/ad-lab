$ErrorActionPreference = 'Continue'
$root = 'C:\Users\vinay\Downloads\ad-lab'
$log  = "$root\logs\phase1-resume-attempt2.log"
$status = "$root\PHASE1-STATUS.md"
function T($m){ ("{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m) | Add-Content -Path $log }
function S($m){ ("- [CLAUDE-RESUME] {0} {1}" -f (Get-Date -Format 'HH:mm'), $m) | Add-Content -Path $status }
$vbm = "$env:ProgramFiles\Oracle\VirtualBox\VBoxManage.exe"
$vms = 'kingslanding','castelblack','winterfell','meereen','braavos'
$ips = @{kingslanding='192.168.56.10';castelblack='192.168.56.11';winterfell='192.168.56.12';meereen='192.168.56.13';braavos='192.168.56.14'}

T "=== PHASE1 RESUME START ==="

# GUARD: must be native (no hypervisor)
$hv = systeminfo 2>$null | Select-String 'A hypervisor has been detected'
$dg = Get-CimInstance -ClassName Win32_DeviceGuard -Namespace root\Microsoft\Windows\DeviceGuard -ErrorAction SilentlyContinue
T ("hypervisor-detected: " + [bool]$hv + " ; VBS status: " + $dg.VirtualizationBasedSecurityStatus)
if ($hv) {
  T "ABORT: hypervisor still active; not starting VMs (would fall to slow NEM)."
  S ("Resume ABORTED: hypervisor still active (VBS " + $dg.VirtualizationBasedSecurityStatus + "). Turn off Memory Integrity in Windows Security > Core isolation, reboot, rerun.")
  exit 1
}
T "Native mode confirmed. Proceeding with vagrant up."

# Bring up the 5 Windows VMs only (skip Codex ansible-control node)
$env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')
$env:AD_LAB_WINRM_PASSWORD = 'vagrant'
Set-Location "$root\infrastructure"
T ("vagrant up " + ($vms -join ' '))
& vagrant up @vms 2>&1 | ForEach-Object { T ("[vagrant] " + $_) }
T ("vagrant up exit=" + $LASTEXITCODE)

# Align local account passwords to Password123! via Guest Additions
foreach ($vm in $vms) {
  $g = "ad-lab-$vm"
  if (-not ((& $vbm list runningvms) -match [regex]::Escape($g))) { T ("SKIP $g (not running)"); continue }
  foreach ($u in 'vagrant','Administrator','labadmin') {
    & $vbm guestcontrol $g run --username vagrant --password vagrant --exe 'C:\Windows\System32\net.exe' -- net.exe user $u 'Password123!' 2>&1 |
      ForEach-Object { T ("[pwd $g $u] " + $_) }
  }
}

# Verify WinRM 5985 on host-only IPs
Start-Sleep -Seconds 5
$ok = @(); $bad = @()
foreach ($vm in $vms) {
  $r = Test-NetConnection -ComputerName $ips[$vm] -Port 5985 -WarningAction SilentlyContinue
  if ($r.TcpTestSucceeded) { $ok += $vm } else { $bad += $vm }
  T ("WinRM " + $ips[$vm] + " (" + $vm + "): " + $r.TcpTestSucceeded)
}
T ("REACHABLE: " + ($ok -join ',') + " | UNREACHABLE: " + ($bad -join ','))

if ($ok.Count -eq 5) {
  S ("PHASE 1 COMPLETE: 5/5 VMs up and reachable at " + (Get-Date -Format 'HH:mm') + ". Ready for Phase 2.")
  T "=== PHASE 1 COMPLETE: 5/5 ==="
} else {
  S ("Phase 1 partial: reachable=" + ($ok -join ',') + " unreachable=" + ($bad -join ',') + ". Diagnose needed.")
  T "=== PHASE 1 PARTIAL ==="
}
T "=== RESUME SCRIPT END ==="
