$a = New-ScheduledTaskAction -Execute powershell.exe -Argument "-NoProfile -ExecutionPolicy Bypass -File $env:USERPROFILE\sysdis.ps1"
Register-ScheduledTask -TaskName sysdis -Action $a -User 'NT AUTHORITY\SYSTEM' -RunLevel Highest -Force | Out-Null
Start-ScheduledTask sysdis; Start-Sleep 8; Get-Content "$env:USERPROFILE\sysdis.log"
Get-ScheduledTask -TaskPath '\Microsoft\Windows\UpdateOrchestrator\*' | select TaskName,State | ft | Out-String
