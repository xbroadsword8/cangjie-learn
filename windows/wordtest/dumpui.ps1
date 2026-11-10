$Out = "$env:USERPROFILE\cjtest\dumpui.log"; Remove-Item $Out -EA SilentlyContinue
Add-Type -AssemblyName System.Windows.Forms, System.Drawing, UIAutomationClient, UIAutomationTypes
$w = New-Object -ComObject Word.Application; $w.Visible = $true
$d = $w.Documents.Add(); $win = $d.Windows(1); $win.DisplayRulers = $true; $win.WindowState = 1
Start-Sleep 3
$root = [Windows.Automation.AutomationElement]::FromHandle([IntPtr]$win.Hwnd)
$all = $root.FindAll([Windows.Automation.TreeScope]::Descendants, [Windows.Automation.Condition]::TrueCondition)
foreach ($e in $all) { $c = $e.Current; if ($c.Name -match '尺|縮|Ruler|Indent|邊界|定位' -or $c.ClassName -match 'Ruler') { "{0} | {1} | {2} | {3}" -f $c.Name, $c.ControlType.ProgrammaticName, $c.ClassName, $c.BoundingRectangle | Out-File $Out -Append -Encoding utf8 } }
$b = [Windows.Forms.Screen]::PrimaryScreen.Bounds
$bmp = New-Object Drawing.Bitmap $b.Width, $b.Height; $g = [Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen(0, 0, 0, 0, $bmp.Size)
$bmp.Save("$env:USERPROFILE\cjtest\screen.png"); "screen $($b.Width)x$($b.Height)" | Out-File $Out -Append -Encoding utf8
$d.Saved = $true; $w.Quit()
