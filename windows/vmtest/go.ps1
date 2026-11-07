# VM 端的步驟入口（ssh 只傳簡單參數，引號都在這裡處理）
param($Step, $File)
$H = $env:USERPROFILE; Set-Location $H
function RunPs($name, $file, $more = '') { & "$H\runi.ps1" $name powershell.exe "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File $H\$file $more" }
function Wait-Task($name) { Start-Sleep 1; while ((Get-ScheduledTask $name).State -eq 'Running') { Start-Sleep 1 } }
switch ($Step) {
  'start' {
    Remove-Item "$env:TEMP\cangjie-learn-setup.log", "$H\*.log" -EA SilentlyContinue
    RunPs probe probe.ps1 '-Seconds 1500'; RunPs autoclick autoclick.ps1 '-Seconds 1200'; Start-Sleep 3
    & "$H\runi.ps1" setup "$H\setup.exe"
  }
  'status' {
    $s = Get-Process setup -EA SilentlyContinue
    "setup_running=$([bool]$s)"
    if (Test-Path "$env:TEMP\cangjie-learn-setup.log") { Get-Content "$env:TEMP\cangjie-learn-setup.log" -Encoding UTF8 | select -Last 3 }
  }
  'focus-old' { RunPs focus focus.ps1; Wait-Task focus; Get-Content "$H\focus.log" }
  'focus-new' {
    Set-WinDefaultInputMethodOverride -InputTip '0404:{35F67E9D-A54D-4177-9697-8B0AB71A9E04}{42D1BA3B-DC86-44CE-AA0B-29BE3392897F}'
    RunPs focus focus.ps1 '-New'; Wait-Task focus; Get-Content "$H\focus.log"
  }
  'run' { RunPs runf $File; Wait-Task runf }
  'read' { RunPs readnote readnote.ps1; Wait-Task readnote; Get-Content "$H\readnote.log" }
  'report' {
    "== setup log"; Get-Content "$env:TEMP\cangjie-learn-setup.log" -Encoding UTF8 -EA SilentlyContinue
    "== autoclick"; Get-Content "$H\autoclick.log" -EA SilentlyContinue
    $l = Get-Content "$H\probe.log"; "== probe lines=$($l.Count) hung-lines:"
    $l | ? { $_ -match 'hung=[1-9]' } | select -First 15
    "== explorer/ctfmon pids seen:"; $l | % { if ($_ -match 'explorer=(\S*) ctfmon=(\S*)') { "$($matches[1]) / $($matches[2])" } } | Get-Unique
  }
}
