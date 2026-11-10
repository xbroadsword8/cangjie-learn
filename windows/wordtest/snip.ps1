# 專測 Win+Shift+S 截圖貼上後輸入法是否還活著；失敗時依序嘗試恢復方式
param($Name = 'snip', $Tip = 'chewing', $Rounds = 4)
$script:Out = "$env:USERPROFILE\cjtest\$Name.log"; Remove-Item $script:Out -EA SilentlyContinue
. "$env:USERPROFILE\cjtest\kb.ps1"
$w = New-Object -ComObject Word.Application; $w.Visible = $true
$d = $w.Documents.Add(); $win = $d.Windows(1); $win.WindowState = 1; Start-Sleep 2; FocusWin $win
$sel = $w.Selection
function Txt { $d.Content.Text }
function GoEnd { $e = $d.Content.End - 1; $d.Range($e, $e).Select() }
function TryType($label) {
  $b = (Txt).Length; Press $script:TIPS[$Tip][2]; Start-Sleep -Milliseconds 600
  $a = Txt; $new = if ($a.Length -gt $b.Length) { $a.Substring($b - 1, $a.Length - $b) } else { '' }
  $ok = $new -match '我'
  Log ("{0} {1} 打出 [{2}]" -f $(if ($ok) { 'OK  ' } else { 'FAIL' }), $label, ($new -replace "`r", '⏎'))
  return $ok
}
function Shot($tag) {
  $bmp = New-Object Drawing.Bitmap 2560, 1440; $g = [Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen(0, 0, 0, 0, $bmp.Size)
  $bmp.Save("$env:USERPROFILE\cjtest\$Name-$tag.png")
}
function Snip {
  Press 'lwin+shift+s'; Start-Sleep 2
  [void][K]::SetCursorPos(1150, 600); Start-Sleep -Milliseconds 300; [K]::mouse_event(2, 0, 0, 0, [UIntPtr]::Zero)
  for ($i = 1; $i -le 15; $i++) { [void][K]::SetCursorPos(1150 + 25 * $i, 600 + 15 * $i); Start-Sleep -Milliseconds 40 }
  [K]::mouse_event(4, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep 2
}
try {
  if (-not (UseTip $Tip { Txt })) { throw "切不到 $Tip" }
  for ($r = 1; $r -le $Rounds; $r++) {
    [void](TryType "r$r 截圖前")
    $n = $d.InlineShapes.Count
    Snip
    FocusWin $win; GoEnd; Press 'ctrl+v'; Start-Sleep -Milliseconds 1500
    Log "     截圖貼上 圖數 $n -> $($d.InlineShapes.Count)"
    GoEnd; Press 'return'
    if (-not (TryType "r$r 截圖貼上後")) {
      Shot "fail$r"
      $t = Txt; $k = $t.Length; for ($j = 0; $j -lt 4; $j++) { Press 'back' }   # 刪掉剛打的 Ji3 與換行
      Press 'shift'; Start-Sleep -Milliseconds 400; if (TryType "  恢復0：按一下 Shift 後") { $script:rec = $true }
      if (-not $script:rec) {
      Press 'escape'; if (TryType "  恢復1：按 Esc 後") { continue }
      FocusWin $win; GoEnd; if (TryType "  恢復2：重新 FocusWin 後") { continue }
      $hr = [Tip]::Activate($script:TIPS[$Tip][0], $script:TIPS[$Tip][1]); Start-Sleep -Milliseconds 800; Log "  重新 ActivateProfile hr=0x$('{0:X}' -f $hr)"
      if (TryType "  恢復3：重新切換輸入法後") { continue }
      $d2 = $w.Documents.Add(); Start-Sleep 1; FocusWin $d2.Windows(1)
      $b = $d2.Content.Text.Length; Press $script:TIPS[$Tip][2]; Start-Sleep -Milliseconds 600
      Log "  恢復4：同一個 Word 開新文件打出 [$($d2.Content.Text)]"
      break
      }
      $script:rec = $false
    }
  }
} catch { Log "ERROR $_" }
finally {
  try { foreach ($x in @($w.Documents)) { $x.Saved = $true }; $w.Quit() } catch { }
  Start-Sleep 2; Get-Process WINWORD -EA SilentlyContinue | ForEach-Object { Log "強制結束 Word $($_.Id)"; $_.Kill() }
  Log 'end'
}
