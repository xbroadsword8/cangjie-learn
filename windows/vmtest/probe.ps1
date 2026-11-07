# 在互動桌面跑：每 0.5 秒對所有可見頂層視窗與工作列送 WM_NULL（逾時 2 秒＝沒回應），寫到 probe.log
param($Seconds = 240, $Out = "$env:USERPROFILE\probe.log")
Add-Type @'
using System; using System.Text; using System.Runtime.InteropServices; using System.Collections.Generic;
public class P {
  public delegate bool EW(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EW f, IntPtr l);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern IntPtr SendMessageTimeout(IntPtr h, uint m, IntPtr w, IntPtr l, uint f, uint t, out IntPtr r);
  public static List<IntPtr> Top() { var l = new List<IntPtr>(); EnumWindows((h, x) => { if (IsWindowVisible(h)) l.Add(h); return true; }, IntPtr.Zero); return l; }
}
'@
$end = (Get-Date).AddSeconds($Seconds)
"start $(Get-Date -Format HH:mm:ss.fff)" | Out-File $Out -Encoding utf8
while ((Get-Date) -lt $end) {
  $t = Get-Date -Format HH:mm:ss.f; $bad = @(); $n = 0
  foreach ($h in [P]::Top()) {
    $c = New-Object Text.StringBuilder 256; [void][P]::GetClassName($h, $c, 256)
    $s = New-Object Text.StringBuilder 256; [void][P]::GetWindowText($h, $s, 256)
    if (-not $s.Length -and $c.ToString() -ne 'Shell_TrayWnd') { continue }
    $n++; $r = [IntPtr]::Zero
    $ok = [P]::SendMessageTimeout($h, 0, [IntPtr]::Zero, [IntPtr]::Zero, 2, 2000, [ref]$r)
    if ($ok -eq [IntPtr]::Zero) { $pid0 = 0; [void][P]::GetWindowThreadProcessId($h, [ref]$pid0); $bad += "$($c)|$($s)|pid=$pid0" }
  }
  $ex = (Get-Process explorer -EA SilentlyContinue | % Id) -join ','; $ct = (Get-Process ctfmon -EA SilentlyContinue | % Id) -join ','
  "$t win=$n hung=$($bad.Count) explorer=$ex ctfmon=$ct $($bad -join ' ; ')" | Out-File $Out -Append -Encoding utf8
  Start-Sleep -Milliseconds 500
}
"end" | Out-File $Out -Append -Encoding utf8
