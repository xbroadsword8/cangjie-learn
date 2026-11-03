# 倉頡學習版（PIME）安裝／移除步驟。由 setup.exe（NSIS）以系統管理員身分呼叫，也可單獨執行：
#   powershell -ExecutionPolicy Bypass -File setup.ps1 -Source <含 cjlearn\ 與 smoke_pime.py 的目錄> [-PimeSetup <PIME 安裝檔>]
#   powershell -ExecutionPolicy Bypass -File setup.ps1 -Uninstall [-RemoveUserData]
# 結束碼：0 成功、1 失敗。過程寫到 %TEMP%\cangjie-learn-setup.log。
param([switch]$Uninstall, [switch]$RemoveUserData, [string]$Source, [string]$PimeSetup, [string]$PimeDir)
$ErrorActionPreference = 'Stop'
$Clsid = '{35F67E9D-A54D-4177-9697-8B0AB71A9E04}'   # PIMETextService
$Guid = '{42D1BA3B-DC86-44CE-AA0B-29BE3392897F}'    # 倉頡學習版的 profile（ime.json）
$Tip = "0404:$Clsid$Guid"
$Log = Join-Path $env:TEMP 'cangjie-learn-setup.log'

function Say($msg) { $line = "$(Get-Date -Format 'HH:mm:ss') $msg"; Write-Output $line; Add-Content -Path $Log -Value $line -Encoding UTF8 }
function Fail($msg) { Say "失敗：$msg"; exit 1 }

function Find-Pime {
    if ($PimeDir) { $c = @($PimeDir) } else {
        $c = @("${env:ProgramFiles(x86)}\PIME", "$env:ProgramFiles\PIME")
        foreach ($k in 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
                       'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*') {
            Get-ItemProperty $k -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName -like 'PIME*' -and $_.UninstallString } |
                ForEach-Object { $c += Split-Path -Parent $_.UninstallString.Trim('"') }
        }
    }
    foreach ($d in $c) { if ($d -and (Test-Path (Join-Path $d 'python\server.py'))) { return (Resolve-Path $d).Path } }
    return $null
}

function Backend-Pids($pime) {
    @(Get-CimInstance Win32_Process -Filter "Name='python.exe'" |
        Where-Object { $_.CommandLine -like '*server.py*' -and $_.ExecutablePath -like "$pime*" } |
        ForEach-Object { $_.ProcessId })
}

function Stop-Backend($pime) { Backend-Pids $pime | ForEach-Object { Stop-Process -Id $_ -Force -ErrorAction SilentlyContinue } }

# PIMELauncher 會自動重開被結束的後端；等它回來
function Restart-Backend($pime) {
    Stop-Backend $pime
    for ($i = 0; $i -lt 20; $i++) {
        Start-Sleep -Milliseconds 500
        if ((Backend-Pids $pime).Count) { Say 'PIME 後端已重新載入'; return }
    }
    Say '注意：PIME 後端沒有自動重開，請登出再登入一次'
}

# 註冊時 PIMETextService.dll 會掃描 input_methods\*\ime.json
function Register-Pime($pime) {
    $jobs = @()
    if ([Environment]::Is64BitOperatingSystem) {
        $jobs += , @("$env:windir\System32\regsvr32.exe", "$pime\x64\PIMETextService.dll")
        $jobs += , @("$env:windir\SysWOW64\regsvr32.exe", "$pime\x86\PIMETextService.dll")
    } else {
        $jobs += , @("$env:windir\System32\regsvr32.exe", "$pime\x86\PIMETextService.dll")
    }
    foreach ($j in $jobs) {
        $p = Start-Process $j[0] -ArgumentList '/s', "`"$($j[1])`"" -Wait -PassThru
        if ($p.ExitCode -ne 0) { Fail "註冊 $($j[1]) 失敗（代碼 $($p.ExitCode)）" }
    }
    Say 'PIME 已重新註冊'
}

function Profile-Keys {
    foreach ($root in 'HKLM:\SOFTWARE\Microsoft\CTF\TIP', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\CTF\TIP', 'HKCU:\SOFTWARE\Microsoft\CTF\TIP') {
        "$root\$Clsid\LanguageProfile\0x00000404\$Guid"
    }
}

function Add-Tip {
    $list = Get-WinUserLanguageList
    if ($list | Where-Object { $_.InputMethodTips -contains $Tip }) { Say '輸入法清單已有倉頡學習版'; return }
    $zh = $list | Where-Object { $_.LanguageTag -eq 'zh-Hant-TW' } | Select-Object -First 1
    if (-not $zh) { Say '注意：語言清單沒有「中文（台灣）」，請到 設定 → 時間與語言 → 語言 加入，再在它的鍵盤加入「倉頡學習版 (PIME)」'; return }
    $zh.InputMethodTips.Add($Tip)
    Set-WinUserLanguageList $list -Force
    Say '已加入輸入法清單'
}

function Remove-Tip {
    $list = Get-WinUserLanguageList
    $changed = $false
    foreach ($l in $list) { if ($l.InputMethodTips -contains $Tip) { [void]$l.InputMethodTips.Remove($Tip); $changed = $true } }
    if ($changed) { Set-WinUserLanguageList $list -Force; Say '已從輸入法清單移除' }
}

Set-Content -Path $Log -Value "倉頡學習版 setup $(Get-Date -Format s) Uninstall=$Uninstall" -Encoding UTF8
$pime = Find-Pime

if ($Uninstall) {
    if (-not $pime) { Say '找不到 PIME，只清理輸入法清單' }
    Remove-Tip
    if ($pime) {
        $dst = Join-Path $pime 'python\input_methods\cjlearn'
        # 後端開著 data\model.db；結束它後趁 PIMELauncher 還沒重開時刪，失敗就重試
        for ($i = 0; (Test-Path $dst) -and $i -lt 10; $i++) {
            Stop-Backend $pime
            Remove-Item $dst -Recurse -Force -ErrorAction SilentlyContinue
            if (Test-Path $dst) { Start-Sleep -Milliseconds 300 }
        }
        if (Test-Path $dst) { Fail "刪不掉 $dst，請登出後再移除一次" }
        Say "已刪除 $dst"
        Register-Pime $pime
    }
    foreach ($k in Profile-Keys) { if (Test-Path $k) { Remove-Item $k -Recurse -Force; Say "已清除 $k" } }
    if ($RemoveUserData) {
        $ud = Join-Path $env:APPDATA 'PIME\cjlearn'
        if (Test-Path $ud) { Remove-Item $ud -Recurse -Force; Say "已刪除學習資料 $ud" }
    } else { Say "學習資料保留在 $env:APPDATA\PIME\cjlearn" }
    if ($pime) { Restart-Backend $pime }
    Say '移除完成'
    exit 0
}

if (-not $Source -or -not (Test-Path (Join-Path $Source 'cjlearn\ime.json'))) { Fail "找不到安裝檔案（-Source $Source）" }
if (-not $pime) {
    if (-not $PimeSetup -or -not (Test-Path $PimeSetup)) { Fail '這台電腦沒有 PIME，且沒有附帶 PIME 安裝檔' }
    Say '這台電腦沒有 PIME，開啟 PIME 1.3.0 安裝程式（請照畫面完成安裝）'
    Start-Process $PimeSetup -Wait
    $pime = Find-Pime
    if (-not $pime) { Fail 'PIME 安裝後仍找不到，請確認 PIME 安裝完成後再執行一次' }
}
Say "PIME：$pime"
foreach ($f in 'python\python3\python.exe', 'python\textService.py', 'python\keycodes.py', 'python\cinbase\icons\chi_half_capsoff.ico') {
    if (-not (Test-Path (Join-Path $pime $f))) { Fail "PIME 缺少 $f（只支援 PIME 1.3）" }
}

$py = Join-Path $pime 'python'
$dst = Join-Path $py 'input_methods\cjlearn'
New-Item -ItemType Directory -Force $dst | Out-Null
Copy-Item (Join-Path $Source 'cjlearn\*') $dst -Recurse -Force
Get-ChildItem $dst -Recurse -Directory -Filter __pycache__ | Remove-Item -Recurse -Force
Say "已複製到 $dst"

# 用 PIME 自己的 Python 模擬打字；沒過就不註冊，避免裝上一個會壞的輸入法
$env:PYTHONIOENCODING = 'utf-8'
$smokeOut = Join-Path $env:TEMP 'cangjie-learn-smoke.txt'
$p = Start-Process (Join-Path $py 'python3\python.exe') -ArgumentList "`"$(Join-Path $Source 'smoke_pime.py')`"", "`"$py`"", "`"$py`"" `
    -Wait -PassThru -NoNewWindow -RedirectStandardOutput $smokeOut -RedirectStandardError "$smokeOut.err"
Get-Content $smokeOut, "$smokeOut.err" -Encoding UTF8 -ErrorAction SilentlyContinue | ForEach-Object { Say "  $_" }
Remove-Item $smokeOut, "$smokeOut.err" -ErrorAction SilentlyContinue
if ($p.ExitCode -ne 0) {
    Stop-Backend $pime
    Remove-Item $dst -Recurse -Force -ErrorAction SilentlyContinue
    Fail '自我測試沒過，已撤回安裝'
}
Say '自我測試通過'

Register-Pime $pime
if (-not (Test-Path (Profile-Keys | Select-Object -First 1))) { Fail '註冊後找不到倉頡學習版的 TSF 設定' }
Restart-Backend $pime
Add-Tip
Say '安裝完成'
exit 0
