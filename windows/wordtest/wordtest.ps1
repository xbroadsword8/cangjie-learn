# 在互動桌面跑：Word 開兩份文件，反覆「打字→貼圖→打字→切文件打字」，用 COM 讀回確認字有沒有進去。
# wordtest.ps1 -Name <紀錄名> -Keys <打一個「我」的按鍵，如 'h,q,i,space' 或 'j,i,3,return'> -Rounds 20 [-Ruler]
param($Name = 'test', $Keys = 'h,q,i,space', $Rounds = 20, [switch]$Ruler)
$Out = "$env:USERPROFILE\cjtest\$Name.log"
Remove-Item $Out -EA SilentlyContinue
function Log($m) { "$(Get-Date -Format HH:mm:ss.fff) $m" | Out-File $Out -Append -Encoding utf8 }
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type @'
using System; using System.Runtime.InteropServices;
public class K {
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  [DllImport("user32.dll")] public static extern uint MapVirtualKey(uint code, uint type);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int x, int y, uint d, UIntPtr e);
  public static void Down(byte vk) { keybd_event(vk, (byte)MapVirtualKey(vk, 0), 0, UIntPtr.Zero); }
  public static void Up(byte vk) { keybd_event(vk, (byte)MapVirtualKey(vk, 0), 2, UIntPtr.Zero); }
  public static void Tap(byte vk) { Down(vk); System.Threading.Thread.Sleep(30); Up(vk); }
}
'@
$VK = @{ space = 0x20; return = 0x0D; ctrl = 0x11; alt = 0x12; escape = 0x1B }
function Press($list) {
  foreach ($k in $list.Split(',')) {
    $v = if ($VK.ContainsKey($k)) { $VK[$k] } elseif ($k -match '^[a-z]$') { [int][char]$k.ToUpper() } elseif ($k -match '^[0-9]$') { [int][char]$k } else { throw "未知按鍵 $k" }
    [K]::Tap([byte]$v); Start-Sleep -Milliseconds 120
  }
}
function Focus($win) {
  $win.Activate()
  $h = [IntPtr]$win.Hwnd
  [void][K]::SetForegroundWindow($h)   # 不按 Alt：在 Word 裡單按 Alt 會叫出功能區快速鍵，後面的字母都被吃掉
  Start-Sleep -Milliseconds 500
}
function CountWo($doc) { ([regex]::Matches($doc.Content.Text, '我')).Count }
function TypeCheck($doc, $label) {
  $before = CountWo $doc
  Press $Keys
  Start-Sleep -Milliseconds 700
  $after = CountWo $doc
  $tail = $doc.Content.Text; if ($tail.Length -gt 12) { $tail = $tail.Substring($tail.Length - 12) }
  $ok = $after -eq $before + 1
  Log ("{0} {1} 我:{2}->{3} 結尾=[{4}]" -f ($(if ($ok) { 'OK  ' } else { 'FAIL' })), $label, $before, $after, ($tail -replace "`r", '⏎'))
  if (-not $ok) {   # 分辨「輸入法壞了」和「按鍵沒送到 Word」：數字鍵輸入法不攔，直接交給 Word
    Press 'escape'
    $n5 = ([regex]::Matches($doc.Content.Text, '5')).Count
    Press '5'; Start-Sleep -Milliseconds 500
    $got5 = ([regex]::Matches($doc.Content.Text, '5')).Count -gt $n5
    Log ("     └ 數字 5 {0}" -f $(if ($got5) { '打得進去 → 輸入法壞了' } else { '也打不進去 → 按鍵沒送到 Word' }))
  }
  return $ok
}
function PasteImage {
  $bmp = New-Object Drawing.Bitmap 240, 120
  $g = [Drawing.Graphics]::FromImage($bmp); $g.Clear([Drawing.Color]::FromArgb((Get-Random 255), 120, 200))
  $g.DrawString((Get-Date -Format HH:mm:ss.fff), (New-Object Drawing.Font 'Arial', 20), [Drawing.Brushes]::Black, 10, 40); $g.Dispose()
  [Windows.Forms.Clipboard]::SetImage($bmp)
  [K]::Down(0x11); [K]::Tap(0x56); [K]::Up(0x11)
  Start-Sleep -Milliseconds 1200
}
function Drag($x1, $x2, $y) {
  [void][K]::SetCursorPos($x1 - 3, $y); Start-Sleep -Milliseconds 300
  [void][K]::SetCursorPos($x1, $y); Start-Sleep -Milliseconds 600     # 先停在標記上，讓 Word 認到
  [K]::mouse_event(2, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 300
  for ($i = 1; $i -le 20; $i++) { [void][K]::SetCursorPos([int]($x1 + ($x2 - $x1) * $i / 20), $y); Start-Sleep -Milliseconds 50 }
  Start-Sleep -Milliseconds 300; [K]::mouse_event(4, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 500
}
function DragRuler($win, $doc) {
  # Win11 測試機 2560x1440、Word 最大化時，縮排 0 的左縮排方塊在 (996,184)（截圖量得）。
  # 每次從 0 拖到右邊 40px，用 COM 確認真的變了，再用 COM 歸零（標記回到 996），下回合才拖得到
  $p = $doc.Paragraphs.Last
  $p.LeftIndent = 0; Start-Sleep -Milliseconds 300
  if (-not $script:shot) { $script:shot = 1
    $bmp = New-Object Drawing.Bitmap 2560, 400; $g = [Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen(0, 0, 0, 0, $bmp.Size)
    $bmp.Save("$env:USERPROFILE\cjtest\shot-$Name.png") }
  for ($try = 1; $try -le 3; $try++) { Drag 996 1036 184; $mid = $p.LeftIndent; if ($mid -ne 0) { break } }
  $p.LeftIndent = 0
  Log ("RULER 左縮排 0 -> {0} 第{2}次 {1}" -f $mid, $(if ($mid -ne 0) { '(有拖到)' } else { '(沒拖到！)' }), $try)
}
try {
  Log "start keys=$Keys rounds=$Rounds ruler=$Ruler"
  $w = New-Object -ComObject Word.Application
  $w.Visible = $true
  $d1 = $w.Documents.Add(); $d2 = $w.Documents.Add()
  $w1 = $d1.Windows(1); $w2 = $d2.Windows(1)
  $w1.DisplayRulers = $true; $w1.WindowState = 1   # 最大化，尺規位置固定
  Start-Sleep 2
  Focus $w1
  $okCount = 0; $fail = 0
  if (-not (TypeCheck $d1 'r0 暖身')) { Log '暖身就失敗：輸入法沒切到或按鍵沒送到'; }
  for ($r = 1; $r -le $Rounds; $r++) {
    $a = TypeCheck $d1 "r$r 貼圖前"
    if ($Ruler) { DragRuler $w1 $d1; Focus $w1 } else { PasteImage }
    $b = TypeCheck $d1 "r$r $(if ($Ruler) { '拖尺規後' } else { '貼圖後' })"
    Focus $w2; $c = TypeCheck $d2 "r$r 文件二"
    Focus $w1
    foreach ($x in $a, $b, $c) { if ($x) { $okCount++ } else { $fail++ } }
  }
  Log "SUMMARY ok=$okCount fail=$fail"
} catch { Log "ERROR $_" }
finally {
  try { foreach ($d in @($w.Documents)) { $d.Saved = $true }; $w.Quit() } catch { Log "close: $_" }
  Start-Sleep 2
  Get-Process WINWORD -EA SilentlyContinue | ForEach-Object { Log "Word 沒關掉，強制結束 $($_.Id)"; $_.Kill() }
  Log 'end'
}
