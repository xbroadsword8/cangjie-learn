# 倉頡學習版（TSF 原生版）安裝／移除步驟。由 setup.exe（NSIS）以系統管理員身分呼叫，也可單獨執行：
#   powershell -ExecutionPolicy Bypass -File setup-tsf.ps1 -Source <含 x64\ x86\ 等檔案的目錄>
#   powershell -ExecutionPolicy Bypass -File setup-tsf.ps1 -Uninstall [-RemoveUserData]
# 結束碼：0 成功、1 失敗。過程寫到 %TEMP%\cangjie-learn-setup.log。
# 會順便移除舊的 PIME 版倉頡學習版（PIME 本身與酷倉不動），學習資料沿用同一個資料夾。
param([switch]$Uninstall, [switch]$RemoveUserData, [string]$Source)
$ErrorActionPreference = 'Stop'
$Clsid = '{979B58A7-ADE5-4333-8493-CA1294B5E806}'
$ProfileGuid = '{C68442D3-78AF-4E6B-8650-8F799C9FF7ED}'
$Tip = "0404:$Clsid$ProfileGuid"
$OldClsid = '{35F67E9D-A54D-4177-9697-8B0AB71A9E04}'   # PIMETextService
$OldGuid = '{42D1BA3B-DC86-44CE-AA0B-29BE3392897F}'    # PIME 版倉頡學習版
$OldTip = "0404:$OldClsid$OldGuid"
$Name = '倉頡學習版'
$Log = Join-Path $env:TEMP 'cangjie-learn-setup.log'
$TaskName = 'CangjieLearnSync'
$UserData = Join-Path $env:APPDATA 'PIME\cjlearn'      # 沿用 PIME 版的位置：學習資料、選項、同步金鑰直接接上
$Dir64 = Join-Path $env:ProgramW6432 'CangjieLearn'
$Dir32 = Join-Path ${env:ProgramFiles(x86)} 'CangjieLearn'
$MinGit = Join-Path $Dir64 'mingit'

function Say($msg) { $line = "$(Get-Date -Format 'HH:mm:ss') $msg"; Write-Output $line; Add-Content -Path $Log -Value $line -Encoding UTF8 }
function Fail($msg) { Say "失敗：$msg"; exit 1 }

# NSIS 是 32 位元，叫起來的 PowerShell 可能也是 32 位元：登錄檔一律明確指定 64／32 位元檢視，不靠轉向
function HKLM($view) {
    [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine,
        $(if ($view -eq 64) { [Microsoft.Win32.RegistryView]::Registry64 } else { [Microsoft.Win32.RegistryView]::Registry32 }))
}
function Set-ComClass($view, $dll) {
    $k = (HKLM $view).CreateSubKey("SOFTWARE\Classes\CLSID\$Clsid")
    $k.SetValue('', $Name)
    $s = $k.CreateSubKey('InprocServer32'); $s.SetValue('', $dll); $s.SetValue('ThreadingModel', 'Apartment')
    $s.Close(); $k.Close()
}
function Remove-ComClass($view) {
    try { (HKLM $view).DeleteSubKeyTree("SOFTWARE\Classes\CLSID\$Clsid", $false) } catch { Say "清除 COM 登錄（$view 位元）：$_" }
}

# 被程式載入中的 DLL 刪不掉：排到下次開機刪
Add-Type -Namespace CJ -Name Native -MemberDefinition '[DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] public static extern bool MoveFileEx(string a, string b, int f);'
function Remove-Locked($path) {
    try { Remove-Item $path -Force -ErrorAction Stop; return $true }
    catch { [void][CJ.Native]::MoveFileEx($path, $null, 4); Say "使用中，下次開機刪除：$path"; return $false }
}
function Prune($dir, $keep) {
    Get-ChildItem $dir -Filter 'cjlearn_tip_*.dll' -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -ne $keep } | ForEach-Object { [void](Remove-Locked $_.FullName) }
}

# --- 輸入法清單 ---
function Set-Tips($add, $remove) {
    $list = Get-WinUserLanguageList
    $zh = $list | Where-Object { $_.LanguageTag -eq 'zh-Hant-TW' } | Select-Object -First 1
    $changed = $false
    foreach ($l in $list) {
        $i = $l.InputMethodTips.IndexOf($remove)
        if ($i -ge 0) {
            $l.InputMethodTips.RemoveAt($i)
            if ($add -and -not ($list | Where-Object { $_.InputMethodTips -contains $add })) { $l.InputMethodTips.Insert($i, $add) }   # 新版放在舊版原本的位置
            $changed = $true
        }
    }
    if ($add -and -not ($list | Where-Object { $_.InputMethodTips -contains $add })) {
        if (-not $zh) { Say "注意：語言清單沒有「中文（台灣）」，請到 設定 → 時間與語言 → 語言 加入，再在它的鍵盤加入「$Name」"; }
        else { $zh.InputMethodTips.Add($add); $changed = $true }
    }
    if ($changed) { Set-WinUserLanguageList $list -Force; Say '已更新輸入法清單' }
}

# --- 舊的 PIME 版 ---
function Find-Pime {
    $c = @("${env:ProgramFiles(x86)}\PIME", "$env:ProgramW6432\PIME")
    foreach ($d in $c) { if (Test-Path (Join-Path $d 'python\server.py')) { return (Resolve-Path $d).Path } }
    return $null
}
function Stop-Backend($pime) {
    Get-CimInstance Win32_Process -Filter "Name='python.exe'" |
        Where-Object { $_.CommandLine -like '*server.py*' -and $_.ExecutablePath -like "$pime*" } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
}
# 移除舊版後要重新註冊 PIME（它會重掃 input_methods）並重開 PIMELauncher，否則酷倉等其他 PIME 輸入法可能卡住
function Restart-Pime($pime) {
    foreach ($j in @("$env:windir\System32\regsvr32.exe", "$pime\x64\PIMETextService.dll"),
                   @("$env:windir\SysWOW64\regsvr32.exe", "$pime\x86\PIMETextService.dll")) {
        $exe = $j[0] -replace '\\System32\\', $(if ([Environment]::Is64BitProcess) { '\System32\' } else { '\Sysnative\' })
        if (Test-Path $j[1]) { Start-Process $exe -ArgumentList '/s', "`"$($j[1])`"" -Wait }
    }
    $exe = Join-Path $pime 'PIMELauncher.exe'
    if (Get-Process PIMELauncher -ErrorAction SilentlyContinue) {
        Start-Process $exe -ArgumentList '/quit' -Wait
        for ($i = 0; $i -lt 20 -and (Get-Process PIMELauncher -ErrorAction SilentlyContinue); $i++) { Start-Sleep -Milliseconds 250 }
        Get-Process PIMELauncher -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }
    Stop-Backend $pime
    $t = 'CangjieLearnStartPime'
    try {
        $me = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        $principal = New-ScheduledTaskPrincipal -UserId $me -LogonType Interactive -RunLevel Limited
        Register-ScheduledTask -TaskName $t -Action (New-ScheduledTaskAction -Execute $exe) -Principal $principal -Force | Out-Null
        Start-ScheduledTask -TaskName $t
        for ($i = 0; $i -lt 20 -and -not (Get-Process PIMELauncher -ErrorAction SilentlyContinue); $i++) { Start-Sleep -Milliseconds 500 }
    } catch { Say "重開 PIME 失敗：$_" }
    finally { Unregister-ScheduledTask -TaskName $t -Confirm:$false -ErrorAction SilentlyContinue }
}
function Remove-OldPime {
    $pime = Find-Pime
    $dst = if ($pime) { Join-Path $pime 'python\input_methods\cjlearn' }
    $oldDir = Join-Path $env:ProgramW6432 'CangjieLearnPIME'
    if (-not ($dst -and (Test-Path $dst)) -and -not (Test-Path $oldDir)) { return }
    Say '移除舊的 PIME 版倉頡學習版（PIME 本身與酷倉保留）'
    if ($dst -and (Test-Path $dst)) {
        for ($i = 0; (Test-Path $dst) -and $i -lt 10; $i++) {
            Stop-Backend $pime
            Remove-Item $dst -Recurse -Force -ErrorAction SilentlyContinue
            if (Test-Path $dst) { Start-Sleep -Milliseconds 300 }
        }
        if (Test-Path $dst) { Say "注意：刪不掉 $dst（登出後可手動刪）" } else { Say "已刪除 $dst" }
    }
    foreach ($view in 64, 32) {
        try { (HKLM $view).DeleteSubKeyTree("SOFTWARE\Microsoft\CTF\TIP\$OldClsid\LanguageProfile\0x00000404\$OldGuid", $false) } catch {}
        try { (HKLM $view).DeleteSubKeyTree('SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\CangjieLearnPIME', $false) } catch {}
    }
    Remove-Item "HKCU:\SOFTWARE\Microsoft\CTF\TIP\$OldClsid\LanguageProfile\0x00000404\$OldGuid" -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path $oldDir) { Remove-Item $oldDir -Recurse -Force -ErrorAction SilentlyContinue; Say "已刪除 $oldDir" }
    if ($pime) { Restart-Pime $pime; Say 'PIME 已重新註冊並重開' }
}

# --- 同步 ---
# MinGit（免安裝的官方 git）＋這台專用的 ssh 金鑰＋每 15 分鐘的排程。版本庫網址由 settings.json 的 sync_remote 決定，沒設就不同步。
function Install-Sync($payload) {
    try {
        $zip = Get-ChildItem $payload -Filter 'MinGit-*-64-bit.zip' | Select-Object -First 1
        if (-not $zip) { Say '安裝包沒有 MinGit，略過同步設定'; return }
        if (Test-Path $MinGit) { Remove-Item $MinGit -Recurse -Force }
        Expand-Archive $zip.FullName $MinGit -Force
        New-Item -ItemType Directory -Force $UserData | Out-Null
        $key = Join-Path $UserData 'sync_key'
        if (-not (Test-Path $key)) {
            $sys = if ([Environment]::Is64BitProcess) { 'System32' } else { 'Sysnative' }
            $kg = Start-Process (Join-Path $env:WINDIR "$sys\OpenSSH\ssh-keygen.exe") -Wait -PassThru -NoNewWindow `
                -ArgumentList "-q -t ed25519 -N `"`" -C cjlearn-$($env:COMPUTERNAME.ToLower()) -f `"$($key -replace '\\','/')`""
            if ($kg.ExitCode -ne 0 -or -not (Test-Path $key)) { throw '產生同步金鑰失敗' }
        }
        Say "同步金鑰（要加到伺服器才能同步）：$(Get-Content "$key.pub")"
        $taskArgs = "`"$UserData`" --git `"$(Join-Path $MinGit 'cmd\git.exe')`" --ssh `"$(Join-Path $MinGit 'usr\bin\ssh.exe')`""
        $action = New-ScheduledTaskAction -Execute (Join-Path $Dir64 'cjlearn-sync.exe') -Argument $taskArgs
        $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 15)
        $me = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        $logon = New-ScheduledTaskTrigger -AtLogOn -User $me
        $principal = New-ScheduledTaskPrincipal -UserId $me -LogonType Interactive
        $opt = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable `
            -ExecutionTimeLimit (New-TimeSpan -Minutes 5) -MultipleInstances IgnoreNew
        Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger, $logon -Principal $principal `
            -Settings $opt -Description '倉頡學習版：同步學習資料' -Force | Out-Null
        Say "已設定排程 $TaskName（每 15 分鐘）"
    } catch { Say "同步設定失敗（輸入法照常可用）：$_" }
}

Set-Content -Path $Log -Value "倉頡學習版（TSF）setup $(Get-Date -Format s) Uninstall=$Uninstall" -Encoding UTF8
if (-not [Environment]::Is64BitOperatingSystem) { Fail '只支援 64 位元 Windows' }

if ($Uninstall) {
    Set-Tips $null $Tip
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) { Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false; Say "已移除排程 $TaskName" }
    if (Test-Path "$Dir64\tsfreg.exe") { & "$Dir64\tsfreg.exe" -u | ForEach-Object { Say "  $_" } }
    Remove-ComClass 64; Remove-ComClass 32
    foreach ($d in $Dir64, $Dir32) {
        if (-not (Test-Path $d)) { continue }
        Prune $d ''
        Get-ChildItem $d -Recurse -File | Where-Object Name -notlike 'cjlearn_tip_*.dll' | Remove-Item -Force -ErrorAction SilentlyContinue
        Get-ChildItem $d -Recurse -Directory | Sort-Object { $_.FullName.Length } -Descending | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
        if (-not (Get-ChildItem $d -ErrorAction SilentlyContinue)) { Remove-Item $d -Force -ErrorAction SilentlyContinue }
        else { [void][CJ.Native]::MoveFileEx($d, $null, 4) }
    }
    if ($RemoveUserData) {
        if (Test-Path $UserData) { Remove-Item $UserData -Recurse -Force; Say "已刪除學習資料 $UserData" }
    } else { Say "學習資料保留在 $UserData" }
    Say '移除完成（若有程式還開著輸入法，部分檔案會在下次開機刪除）'
    exit 0
}

foreach ($f in 'x64\cjlearn_tip.dll', 'x86\cjlearn_tip.dll', 'model.db', 'tsfreg.exe', 'cjlearn.ico', 'cjlearn-sync.exe') {
    if (-not $Source -or -not (Test-Path (Join-Path $Source $f))) { Fail "安裝檔案缺少 $f（-Source $Source）" }
}

Remove-OldPime

# DLL 用帶時間戳的檔名：舊版若正被程式載入會鎖住無法覆蓋；登錄檔指向新檔後，新開的程式就用新版
$stamp = Get-Date -Format 'yyyyMMddHHmmss'
New-Item -ItemType Directory -Force $Dir64, $Dir32 | Out-Null
$dll64 = Join-Path $Dir64 "cjlearn_tip_$stamp.dll"; $dll32 = Join-Path $Dir32 "cjlearn_tip_$stamp.dll"
Copy-Item (Join-Path $Source 'x64\cjlearn_tip.dll') $dll64 -Force
Copy-Item (Join-Path $Source 'x86\cjlearn_tip.dll') $dll32 -Force
foreach ($d in $Dir64, $Dir32) {
    # model.db 可能正被舊版 DLL 開著（唯讀）：先改名再放新檔，舊檔排到開機刪
    $m = Join-Path $d 'model.db'
    if (Test-Path $m) { $old = "$m.old-$stamp"; try { Move-Item $m $old -Force; [void](Remove-Locked $old) } catch { Say "注意：model.db 換不掉：$_" } }
    Copy-Item (Join-Path $Source 'model.db') $m -Force
    Remove-Item (Join-Path $d 'data_dir.txt') -ErrorAction SilentlyContinue   # 開發測試用的設定不帶進正式版
}
foreach ($f in 'tsfreg.exe', 'cjlearn.ico', 'cjlearn-sync.exe') { Copy-Item (Join-Path $Source $f) $Dir64 -Force }
Say "已複製到 $Dir64、$Dir32"

Set-ComClass 64 $dll64
Set-ComClass 32 $dll32
$out = & (Join-Path $Dir64 'tsfreg.exe') -r (Join-Path $Dir64 'cjlearn.ico') 2>&1
$out | ForEach-Object { Say "  $_" }
$k = (HKLM 64).OpenSubKey("SOFTWARE\Microsoft\CTF\TIP\$Clsid\LanguageProfile\0x00000404\$ProfileGuid")
if (-not $k) { Fail '註冊後找不到倉頡學習版的 TSF 設定' }
$k.Close()
Say 'TSF 已註冊'

Set-Tips $Tip $OldTip
Install-Sync $Source
Prune $Dir64 $dll64; Prune $Dir32 $dll32
# 之前開發測試留下的資料夾（同一個 CLSID，登錄檔已改指向正式版）
foreach ($d in (Join-Path $env:ProgramW6432 'CangjieLearnTSF'), (Join-Path ${env:ProgramFiles(x86)} 'CangjieLearnTSF')) {
    if (Test-Path $d) { Get-ChildItem $d -File | ForEach-Object { [void](Remove-Locked $_.FullName) }; Remove-Item $d -Force -Recurse -ErrorAction SilentlyContinue; Say "已清除開發版 $d" }
}
Say '安裝完成'
exit 0
