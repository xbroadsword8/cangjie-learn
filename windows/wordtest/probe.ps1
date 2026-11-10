# 測新酷音各標點組合實際送出什麼
param($Name = 'probe')
$script:Out = "$env:USERPROFILE\cjtest\$Name.log"; Remove-Item $script:Out -EA SilentlyContinue
. "$env:USERPROFILE\cjtest\kb.ps1"
$w = New-Object -ComObject Word.Application; $w.Visible = $true
$d = $w.Documents.Add(); $win = $d.Windows(1); $win.WindowState = 1; Start-Sleep 2; FocusWin $win
if (-not (UseTip 'chewing' { $d.Content.Text })) { Log '切不到新酷音'; $d.Saved = $true; $w.Quit(); exit }
$K = 'oem_comma','oem_period','oem_1','oem_2','oem_7','oem_4','oem_6','oem_5','oem_3','oem_minus','oem_plus','1','9','0','8','6'
$tests = @('oem_4', 'oem_6', 'oem_5', 'oem_7', 'oem_3', 'escape', 'shift+oem_comma shift+oem_comma', 'oem_comma', 'ctrl+oem_1')
foreach ($t in $tests) {
  $before = $d.Content.Text
  Press $t; Start-Sleep -Milliseconds 300; Press 'return'; Start-Sleep -Milliseconds 400
  $after = $d.Content.Text
  $new = if ($after.Length -ge $before.Length) { $after.Substring($before.Length - 1, $after.Length - $before.Length) } else { '<變短>' }
  Log ("{0,-18} => [{1}]" -f $t, ($new -replace "`r", '⏎'))
}
$d.Saved = $true; $w.Quit()
