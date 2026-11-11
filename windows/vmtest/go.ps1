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
    # tip.txt（trial.sh 依 TIP 變數放上來）指定要測的輸入法；沒有就是 PIME 版倉頡學習版
    $tip = if (Test-Path "$H\tip.txt") { (Get-Content "$H\tip.txt" -Raw).Trim() } else { '0404:{35F67E9D-A54D-4177-9697-8B0AB71A9E04}{42D1BA3B-DC86-44CE-AA0B-29BE3392897F}' }
    Set-WinDefaultInputMethodOverride -InputTip $tip
    RunPs focus focus.ps1 '-New'; Wait-Task focus; Get-Content "$H\focus.log"
  }
  'run' { RunPs runf $File; Wait-Task runf }
  'read' { RunPs readnote readnote.ps1; Wait-Task readnote; Get-Content "$H\readnote.log" }
  'tips' { "== 輸入法清單"; (Get-WinUserLanguageList).InputMethodTips; "== 解除安裝項目"; Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*' -EA SilentlyContinue | ? DisplayName -like '倉頡*' | select DisplayName, DisplayVersion | Out-String; "== 排程"; Get-ScheduledTask CangjieLearnSync -EA SilentlyContinue | select TaskName, State | Out-String; "== 檔案"; gci "$env:ProgramW6432\CangjieLearn", "${env:ProgramFiles(x86)}\CangjieLearn", "${env:ProgramFiles(x86)}\PIME\python\input_methods" -EA SilentlyContinue | select FullName | Out-String }
  'uninstall' { & "$H\runi.ps1" uninst "$env:ProgramW6432\CangjieLearn\uninstall.exe" '/S' -Wait; Start-Sleep 5; Get-Content "$env:TEMP\cangjie-learn-setup.log" -Encoding UTF8 -EA SilentlyContinue }
  'report' {
    "== setup log"; Get-Content "$env:TEMP\cangjie-learn-setup.log" -Encoding UTF8 -EA SilentlyContinue
    "== autoclick"; Get-Content "$H\autoclick.log" -EA SilentlyContinue
    $l = Get-Content "$H\probe.log"; "== probe lines=$($l.Count) hung-lines:"
    $l | ? { $_ -match 'hung=[1-9]' } | select -First 15
    "== explorer/ctfmon pids seen:"; $l | % { if ($_ -match 'explorer=(\S*) ctfmon=(\S*)') { "$($matches[1]) / $($matches[2])" } } | Get-Unique
  }
}
