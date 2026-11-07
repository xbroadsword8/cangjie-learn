foreach ($s in 'wuauserv','UsoSvc','BITS','DoSvc') { Stop-Service $s -Force -EA SilentlyContinue; Set-Service $s -StartupType Disabled -EA SilentlyContinue }
$k='HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'; New-Item $k -Force | Out-Null
Set-ItemProperty $k NoAutoUpdate 1 -Type DWord; Set-ItemProperty $k NoAutoRebootWithLoggedOnUsers 1 -Type DWord
Get-ScheduledTask -TaskPath '\Microsoft\Windows\UpdateOrchestrator\*','\Microsoft\Windows\WindowsUpdate\*' -EA SilentlyContinue | % { try { Disable-ScheduledTask -InputObject $_ -EA Stop | Out-Null; "disabled $($_.TaskName)" } catch { "skip $($_.TaskName)" } }
shutdown /a 2>$null
Get-Service wuauserv,UsoSvc | select Name,Status,StartType | ft | Out-String
