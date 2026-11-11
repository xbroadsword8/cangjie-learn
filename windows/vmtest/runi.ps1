# 在已登入的桌面（互動工作階段）以最高權限執行指令：runi.ps1 <名稱> <exe> [參數]
param($Name, $Exe, $Arg = '', [switch]$Wait)
$a = if ($Arg) { New-ScheduledTaskAction -Execute $Exe -Argument $Arg } else { New-ScheduledTaskAction -Execute $Exe }
$p = New-ScheduledTaskPrincipal -UserId ((Get-CimInstance Win32_ComputerSystem).UserName) -LogonType Interactive -RunLevel Highest   # ssh 登入時 USERDOMAIN 是 WORKGROUP，不能拿來拼
Register-ScheduledTask -TaskName $Name -Action $a -Principal $p -Force | Out-Null
Start-ScheduledTask $Name
if ($Wait) { do { Start-Sleep 1 } while ((Get-ScheduledTask $Name).State -eq 'Running'); (Get-ScheduledTaskInfo $Name).LastTaskResult }
