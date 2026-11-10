# TSF 版倉頡學習版冒煙測試：Word 新文件逐項打字，用 COM 讀回比對。tsfsmoke.ps1 -Name <紀錄名> [-Tip cjtsf]
param($Name = 'tsfsmoke', $Tip = 'cjtsf')
$script:Out = "$env:USERPROFILE\cjtest\$Name.log"; Remove-Item $script:Out -EA SilentlyContinue
. "$env:USERPROFILE\cjtest\kb.ps1"
$w = New-Object -ComObject Word.Application; $w.Visible = $true
$d = $w.Documents.Add(); $win = $d.Windows(1); $win.WindowState = 1; Start-Sleep 2; FocusWin $win
function Txt { $d.Content.Text }
function Shot($tag) {
  $bmp = New-Object Drawing.Bitmap 2560, 1440; $g = [Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen(0, 0, 0, 0, $bmp.Size)
  $bmp.Save("$env:USERPROFILE\cjtest\$Name-$tag.png")
}
$pass = 0; $fail = 0
function Case($label, $keys, $want) {
  $b = Txt; Press $keys; Start-Sleep -Milliseconds 700; $a = Txt
  $new = if ($a.Length -ge $b.Length) { $a.Substring($b.Length - 1, $a.Length - $b.Length) } else { "(變短)" }
  $ok = $new -ceq $want
  if ($ok) { $script:pass++ } else { $script:fail++ }
  Log ("{0} {1}：要 [{2}] 得 [{3}]" -f $(if ($ok) { 'PASS' } else { 'FAIL' }), $label, $want, ($new -replace "`r", '⏎'))
}
try {
  if (-not (UseTip $Tip { Txt })) { Log 'FAIL 切不到輸入法'; return }
  Case '基本組字 我倉' 'h q i space o i a r space' '我倉'
  Case '上文選字 恭喜' 't c p space g r t r space' '恭喜'
  Case '組字中逗號→送字＋半形' 'h q i oem_comma' '我,'
  Case '沒組字句號→半形' 'oem_period' '.'
  Case 'Ctrl+, → ，' 'ctrl+oem_comma' '，'
  Case 'Ctrl+. → 。' 'ctrl+oem_period' '。'
  Case 'Ctrl+Shift+/ → ？' 'ctrl+shift+oem_2' '？'
  Case 'Ctrl+[ ] → 「」' 'ctrl+oem_4 ctrl+oem_6' '「」'
  Case '單按 Shift 切英文' 'shift a b' 'ab'
  Case '再按 Shift 回中文' 'shift a space' '日'
  Case '打錯碼按空白清掉' 'q q q q space h q i space' '我'
  Case 'Esc 取消組字' 'h q escape' ''
  Case 'Backspace 刪碼' 'h q i back back space' ''
  Press 'escape'
  # 補完候選與灰色字根：截圖給人看
  Press 'h q'; Start-Sleep -Milliseconds 800; Shot 'cand-hq'; Press 'escape'
  # Win+Shift+S：取消截圖後應仍是中文
  Press 'lwin+shift+s'; Start-Sleep 2; Press 'escape'; Start-Sleep 1; FocusWin $win
  Case 'Win+Shift+S 之後仍是中文' 'h q i space' '我'
  Press 'lwin+shift+s'; Start-Sleep 2; Press 'escape'; Start-Sleep 1; FocusWin $win
  Case '再一次 Win+Shift+S' 'o i a r space' '倉'
} catch { Log "ERROR $_" } finally {
  Log "SUMMARY pass=$pass fail=$fail"
  Log ("全文 [{0}]" -f ((Txt) -replace "`r", '⏎'))
  $d.Saved = $true; try { $w.Quit() } catch {}
  Start-Sleep 2; Get-Process WINWORD -EA SilentlyContinue | Stop-Process -Force
}
