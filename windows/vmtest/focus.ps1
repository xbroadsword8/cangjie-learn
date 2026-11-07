# 在互動桌面跑：把指定程式的主視窗帶到前景（新開一個或拿既有的），結果寫 focus.log
param([switch]$New, $Out = "$env:USERPROFILE\focus.log")
Add-Type @'
using System; using System.Runtime.InteropServices;
public class F { [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
 [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
 [DllImport("user32.dll")] public static extern void keybd_event(byte k, byte s, uint f, IntPtr e);
 [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow(); }
'@
if ($New) { $p = Start-Process notepad -PassThru; Start-Sleep 3; $p.Refresh() } else { $p = Get-Process notepad | sort StartTime | select -First 1 }
$h = $p.MainWindowHandle
if ([F]::GetForegroundWindow() -ne $h) { [F]::keybd_event(0x12, 0, 0, [IntPtr]::Zero); [F]::keybd_event(0x12, 0, 2, [IntPtr]::Zero) }  # 按 Alt 才能搶前景；已在前景就別按（會進選單）
[F]::ShowWindow($h, 9) | Out-Null; $ok = [F]::SetForegroundWindow($h)
Start-Sleep -Milliseconds 500
"pid=$($p.Id) fg=$([F]::GetForegroundWindow() -eq $h) ok=$ok" | Out-File $Out -Encoding utf8
