# 在已登入的桌面跑 wordtest.ps1 並等它結束：runwt.ps1 <紀錄名> <按鍵> <回合> [ruler]
param($Name, $Keys, $Rounds = 20, $Mode = '', $Max = 900)
$script = "$env:USERPROFILE\cjtest\$(if ($Name -match "^(dumpui|probe3|probe|snip)") { "$($Matches[1]).ps1" } elseif ($Name -match "^retype") { "retype.ps1" } else { "wordtest.ps1" })"
$arg = "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File `"$script`" -Name $Name -Keys $Keys -Rounds $Rounds"
if ($Mode -eq 'ruler') { $arg += ' -Ruler' }
if ($Name -match '^snip') { $arg = "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File `"$script`" -Name $Name -Rounds $Rounds -Tip $(if ($Name -match 'pime') { 'cjlearn' } else { 'chewing' })" }
if ($Name -match '^retype') { $arg = "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File `"$script`" -Name $Name -Limit $Rounds" }
$a = New-ScheduledTaskAction -Execute powershell.exe -Argument $arg
$p = New-ScheduledTaskPrincipal -UserId ((Get-CimInstance Win32_ComputerSystem).UserName) -LogonType Interactive -RunLevel Limited
Register-ScheduledTask -TaskName cjwt -Action $a -Principal $p -Force | Out-Null
Start-ScheduledTask cjwt
$t0 = Get-Date
do { Start-Sleep 2 } while ((Get-ScheduledTask cjwt).State -eq 'Running' -and ((Get-Date) - $t0).TotalSeconds -lt $Max)
if ((Get-ScheduledTask cjwt).State -eq 'Running') { Stop-ScheduledTask cjwt; 'TIMEOUT 已停止' }
Unregister-ScheduledTask -TaskName cjwt -Confirm:$false
[Console]::OutputEncoding = [Text.Encoding]::UTF8
Get-Content "$env:USERPROFILE\cjtest\$Name.log" -EA SilentlyContinue
