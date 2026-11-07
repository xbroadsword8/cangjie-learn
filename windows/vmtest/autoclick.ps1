# 在互動桌面跑：像使用者一路按「下一步」把安裝精靈走完，紀錄到 autoclick.log
# NSIS／訊息框：直接對按鈕 ID 送 BM_CLICK（1＝下一步/安裝/同意/完成/確定，6＝是）；VC++（WiX）用 UIA
param($Seconds = 1200, $Out = "$env:USERPROFILE\autoclick.log")
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
Add-Type @'
using System; using System.Text; using System.Runtime.InteropServices; using System.Collections.Generic;
public class W {
  public delegate bool EW(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EW f, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr p, EW f, IntPtr l);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsWindowEnabled(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetDlgItem(IntPtr h, int id);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern IntPtr PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  public static List<IntPtr> Top() { var l = new List<IntPtr>(); EnumWindows((h, x) => { if (IsWindowVisible(h)) l.Add(h); return true; }, IntPtr.Zero); return l; }
  public static string Txt(IntPtr h) { var s = new StringBuilder(512); GetWindowText(h, s, 512); return s.ToString(); }
  public static string Cls(IntPtr h) { var s = new StringBuilder(256); GetClassName(h, s, 256); return s.ToString(); }
  public static string AllText(IntPtr p) { var sb = new StringBuilder(); EnumChildWindows(p, (h, x) => { if (IsWindowVisible(h) && Cls(h) == "Static") sb.Append(Txt(h)).Append(" / "); return true; }, IntPtr.Zero); return sb.ToString(); }
}
'@
$A = [Windows.Automation.AutomationElement]; $TS = [Windows.Automation.TreeScope]
function Log($m) { "$(Get-Date -Format HH:mm:ss) $m" | Out-File $Out -Append -Encoding utf8 }
$end = (Get-Date).AddSeconds($Seconds); Log 'start'
while ((Get-Date) -lt $end) {
  try {
    foreach ($h in [W]::Top()) {
      $pid0 = 0; [void][W]::GetWindowThreadProcessId($h, [ref]$pid0)
      $pn = (Get-Process -Id $pid0 -EA SilentlyContinue).Name
      if ($pn -notmatch '^(setup|PIME.*|Au_.*|vc_redist.*)$') { continue }
      $title = [W]::Txt($h)
      if ([W]::Cls($h) -eq '#32770') {
        foreach ($id in 6, 1) {
          $b = [W]::GetDlgItem($h, $id)
          if ($b -ne [IntPtr]::Zero -and [W]::IsWindowVisible($b) -and [W]::IsWindowEnabled($b)) {
            Log "[$pn] [$title] click id=$id '$([W]::Txt($b))' :: $([W]::AllText($h))"
            [void][W]::PostMessage($b, 0xF5, [IntPtr]::Zero, [IntPtr]::Zero); Start-Sleep 2; break
          }
        }
      } elseif ($title -match 'Visual C\+\+') {
        $w = $A::FromHandle($h)
        foreach ($e in $w.FindAll($TS::Descendants, [Windows.Automation.Condition]::TrueCondition)) {
          $c = $e.Current; if (-not $c.IsEnabled) { continue }
          if ($c.ControlType -eq [Windows.Automation.ControlType]::CheckBox) {
            $tp = $e.GetCurrentPattern([Windows.Automation.TogglePattern]::Pattern)
            if ($tp.Current.ToggleState -ne 'On') { $tp.Toggle(); Log "[vc] toggle $($c.Name)" }
          }
        }
        $ok = $w.FindFirst($TS::Descendants, (New-Object Windows.Automation.PropertyCondition($A::NameProperty, 'Setup Successful')))
        $want = if ($ok) { 'Close' } else { 'Install' }
        $btn = $w.FindFirst($TS::Descendants, (New-Object Windows.Automation.PropertyCondition($A::NameProperty, $want)))
        if ($btn -and $btn.Current.IsEnabled) { Log "[vc] click $want"; $btn.GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern).Invoke(); Start-Sleep 3 }
      }
    }
  } catch { Log "err $($_.Exception.Message)" }
  Start-Sleep 1
}
Log 'end'
