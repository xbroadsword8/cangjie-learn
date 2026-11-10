# 開發用安裝（不走 MSI）：系統管理員執行。devinstall.ps1 <放 x64\ x86\ tsfreg.exe icon model.db 的資料夾>
#   -DataDir <資料夾>：寫 data_dir.txt，學習資料改放那裡（可含 %APPDATA% 等，由 DLL 展開）；測試時用來隔開真正的 user.db 與同步
#   devinstall.ps1 -Uninstall    取消註冊並刪掉安裝資料夾（載入中的 DLL 刪不掉會留著，重開機後再跑一次）
# DLL 用帶時間戳的檔名：已載入的舊 DLL 被鎖住無法覆蓋，新開的程式會載入登錄檔指向的新檔。
param($Src, $DataDir, [switch]$Uninstall)
$ErrorActionPreference = 'Stop'
$clsid = '{979B58A7-ADE5-4333-8493-CA1294B5E806}'
$name = '倉頡學習版 (TSF)'
$d64 = "$env:ProgramW6432\CangjieLearnTSF"
$d32 = "${env:ProgramFiles(x86)}\CangjieLearnTSF"

function SetClass($root, $dll) {
  $k = "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\$root\CLSID\$clsid"
  New-Item -Path "$k\InprocServer32" -Force | Out-Null
  Set-ItemProperty -Path $k -Name '(default)' -Value $name
  Set-ItemProperty -Path "$k\InprocServer32" -Name '(default)' -Value $dll
  Set-ItemProperty -Path "$k\InprocServer32" -Name ThreadingModel -Value Apartment
}
function Prune($dir, $keep) {
  Get-ChildItem $dir -Filter 'cjlearn_tip_*.dll' -EA SilentlyContinue | Where-Object FullName -ne $keep |
    ForEach-Object { try { Remove-Item $_.FullName -Force } catch { "（還在使用中，留著）$($_.Name)" } }
}

if ($Uninstall) {
  if (Test-Path "$d64\tsfreg.exe") { & "$d64\tsfreg.exe" -u | Out-Host }
  foreach ($r in 'Classes', 'Classes\WOW6432Node') {
    Remove-Item "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\$r\CLSID\$clsid" -Recurse -Force -EA SilentlyContinue
  }
  foreach ($d in $d64, $d32) { Prune $d ''; Remove-Item $d -Recurse -Force -EA SilentlyContinue }
  '已取消註冊'
  return
}

$stamp = Get-Date -Format 'yyyyMMddHHmmss'
New-Item -ItemType Directory -Force $d64, $d32 | Out-Null
$dll64 = "$d64\cjlearn_tip_$stamp.dll"; $dll32 = "$d32\cjlearn_tip_$stamp.dll"
Copy-Item "$Src\x64\cjlearn_tip.dll" $dll64
Copy-Item "$Src\x86\cjlearn_tip.dll" $dll32
foreach ($d in $d64, $d32) { Copy-Item "$Src\model.db" "$d\model.db" -Force }
foreach ($d in $d64, $d32) {
  if ($DataDir) { Set-Content -Path "$d\data_dir.txt" -Value $DataDir -Encoding UTF8 } else { Remove-Item "$d\data_dir.txt" -EA SilentlyContinue }
}
Copy-Item "$Src\tsfreg.exe", "$Src\cjlearn.ico" $d64 -Force
SetClass 'Classes' $dll64
SetClass 'Classes\WOW6432Node' $dll32
& "$d64\tsfreg.exe" -r "$d64\cjlearn.ico" | Out-Host
Prune $d64 $dll64; Prune $d32 $dll32
"已安裝 $stamp"
