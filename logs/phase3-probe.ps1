# Phase 3 lightweight health probe — emits one parseable line. Read-only.
$ErrorActionPreference='SilentlyContinue'
$vbm="$env:ProgramFiles\Oracle\VirtualBox\VBoxManage.exe"
$os=Get-CimInstance Win32_OperatingSystem
$ram=[int]($os.FreePhysicalMemory/1024)
$disk=[int]((Get-PSDrive C).Free/1GB)
$cpu=[int]((Get-CimInstance Win32_Processor | Measure-Object LoadPercentage -Average).Average)
$vms=((& $vbm list runningvms) | Measure-Object).Count
$down=@()
foreach($i in 10,11,12,13,14){ if(-not (Test-NetConnection "192.168.56.$i" -Port 5985 -WarningAction SilentlyContinue).TcpTestSucceeded){ $down+=$i } }
"RAM=$ram;DISK=$disk;CPU=$cpu;VMS=$vms;DOWN=$($down -join '_')"
