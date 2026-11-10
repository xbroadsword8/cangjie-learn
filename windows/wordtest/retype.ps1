# 照 plan.json 在 Word 重打論文片段（經目前預設輸入法），每步驗證；輸入法死掉就停。
# retype.ps1 -Name <紀錄名> [-Limit <最多幾個頂層操作>]
param($Name = 'retype', $Limit = 0)
$script:Out = "$env:USERPROFILE\cjtest\$Name.log"; Remove-Item $script:Out -EA SilentlyContinue
. "$env:USERPROFILE\cjtest\kb.ps1"
$Base = "$env:USERPROFILE\cjtest\retype"
$plan = Get-Content "$Base\plan.json" -Encoding UTF8 -Raw | ConvertFrom-Json
$STY = @{ h1 = -2; h2 = -3; h3 = -4; normal = -1; caption = -35; quote = -181; list = -180 }
$stat = @{ zh = 0; zhChars = 0; punct = 0; ascii = 0; warn = 0; img = 0; ruler = 0; table = 0; footnote = 0; citation = 0; caption = 0 }
$script:last = @()      # 最近做過的「觸發型」操作，死掉時回報
class Dead : Exception { Dead($m) : base($m) {} }

function CJK($s) { ([regex]::Matches($s, '[\u4e00-\u9fff]')).Count }
function ALNUM($s) { ([regex]::Matches($s, '[A-Za-z0-9]')).Count }
$script:inHeader = $false
function ParaText {
  try {
    # 讀整個故事（正文／註腳／頁首）而不是目前段落：英文模式下按 Enter 會換段，只看段落會漏掉打出的字母
    if ($script:inHeader) { $script:d.Sections($script:d.Sections.Count).Headers(1).Range.Text }
    else { $script:d.StoryRanges.Item($script:sel.StoryType).Text }
  } catch { '' }
}
function GoEnd { $e = $script:d.Content.End - 1; $script:d.Range($e, $e).Select() }
function Trig($m) { $script:last = @($script:last + $m) | Select-Object -Last 6 }
function DeadCheck($what) {
  Press 'escape'
  $n5 = ([regex]::Matches((ParaText), '5')).Count
  Press 'num5'; Start-Sleep -Milliseconds 400
  if (([regex]::Matches((ParaText), '5')).Count -gt $n5) {
    Press 'back'; Start-Sleep -Milliseconds 300
    # 再打一個一定打得出來的「我」：打得出來代表只是那組鍵無效（例如不存在的注音），不是輸入法死掉
    $b = CJK (ParaText); Press 'j i 3 return'; Start-Sleep -Milliseconds 500
    if ((CJK (ParaText)) -gt $b) { Press 'back'; $stat.warn++; Log "WARN $what 打不出字，但測試字「我」打得出來：按鍵組合無效，不是輸入法死掉"; return $false }
    throw [Dead]::new("輸入法死了（$what 打不出字，數字鍵盤 5 打得進去）。之前的操作：$($script:last -join ' → ')")
  }
  return $false
}
function RunText($ops) {
  foreach ($o in $ops) {
    switch ($o.op) {
      'zh' {
        $t0s = ParaText; $b = CJK $t0s; $bl = $t0s.Length; $ba = ALNUM $t0s
        Press $o.keys; Start-Sleep -Milliseconds 150
        $got = (CJK (ParaText)) - $b
        if ($got -eq 0) { Start-Sleep -Milliseconds 800; $got = (CJK (ParaText)) - $b }
        if ($got -eq 0) {
          $now = ParaText; $al = (ALNUM $now) - $ba
          if ($al -gt 0) {   # 注音鍵變成英文字母：輸入法在英文模式或還沒接上，不是死掉
            Log "MODE 「$($o.text)」 打成英數 [$($now.Substring([Math]::Max(0,$bl-1)).Trim())]，刪掉、切回中文重打"
            for ($k = 0; $k -lt ($now.Length - $bl); $k++) { Press 'back' }
            Press 'shift'; Start-Sleep -Milliseconds 300
            Press $o.keys; Start-Sleep -Milliseconds 400; $got = (CJK (ParaText)) - $b
            if ($got -eq 0) { throw [Dead]::new("「$($o.text)」 切換中英後仍打成英數，輸入法狀態不明") }
          } else {
            DeadCheck "「$($o.text)」"
            FocusWin $script:win; Log "RETRY 「$($o.text)」 沒出字、數字鍵也沒進去，重新取得焦點重打"
            Press $o.keys; Start-Sleep -Milliseconds 400; $got = (CJK (ParaText)) - $b
            if ($got -eq 0) { throw [Dead]::new("「$($o.text)」 重打仍沒出字，且數字鍵也打不進去（按鍵沒送到 Word）") }
          }
        }
        if ($got -ne $o.n) { $stat.warn++; Log "WARN 字數 「$($o.text)」 應 $($o.n) 得 $got" }
        $stat.zh++; $stat.zhChars += $got
      }
      'punct' {
        $b = (ParaText).Length; Press $o.keys; Start-Sleep -Milliseconds 120
        if ((ParaText).Length -le $b) { Start-Sleep -Milliseconds 600; if ((ParaText).Length -le $b) { DeadCheck "標點 $($o.ch)"; $stat.warn++; Log "WARN 標點 $($o.ch) 沒出來" } }
        $stat.punct++
      }
      'ascii' {
        $b = ALNUM (ParaText)
        Press 'shift'; [K]::Ascii($o.text); Press 'shift'; Start-Sleep -Milliseconds 120
        $want = ALNUM $o.text; $got = (ALNUM (ParaText)) - $b
        if ($got -ne $want) { $stat.warn++; Log "WARN 英數 [$($o.text)] 應 $want 得 $got" }
        $stat.ascii++
      }
      'com' { $script:sel.TypeText($o.text) }
    }
  }
}
function Img($o) {
  $path = "$Base\media\$($o.file)"; $n = $script:d.InlineShapes.Count
  switch ($o.method) {
    'addpic' { [void]$script:sel.InlineShapes.AddPicture($path) }
    'clip'   { $im = [Drawing.Image]::FromFile($path); [Windows.Forms.Clipboard]::SetImage($im); $im.Dispose(); Press 'ctrl+v' }
    'copy'   { if ($n -gt 0) { $script:d.InlineShapes(1).Select(); Press 'ctrl+c'; GoEnd; Press 'ctrl+v' } else { $im = [Drawing.Image]::FromFile($path); [Windows.Forms.Clipboard]::SetImage($im); $im.Dispose(); Press 'ctrl+v' } }
    'snip'   {
      Press 'lwin+shift+s'; Start-Sleep 2
      [void][K]::SetCursorPos(1150, 600); Start-Sleep -Milliseconds 300; [K]::mouse_event(2, 0, 0, 0, [UIntPtr]::Zero)
      for ($i = 1; $i -le 15; $i++) { [void][K]::SetCursorPos(1150 + 25 * $i, 600 + 15 * $i); Start-Sleep -Milliseconds 40 }
      [K]::mouse_event(4, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep 2
      FocusWin $script:win; GoEnd; Press 'ctrl+v'
    }
  }
  Start-Sleep -Milliseconds 1200
  $m = $script:d.InlineShapes.Count
  if ($m -gt $n) { $s = $script:d.InlineShapes($m); if ($s.Width -gt 400) { $s.LockAspectRatio = -1; $s.Width = 400 } }
  Log ("IMG {0} {1} 圖數 {2}->{3}{4}" -f $o.method, $o.file, $n, $m, $(if ($m -gt $n) { '' } else { ' ⚠ 沒貼上' }))
  GoEnd; $stat.img++; Trig "圖片($($o.method))"
}
function Ruler {
  $p = $script:sel.Paragraphs(1); $p.LeftIndent = 0; Start-Sleep -Milliseconds 300
  for ($t = 1; $t -le 3; $t++) {
    [void][K]::SetCursorPos(993, 184); Start-Sleep -Milliseconds 300; [void][K]::SetCursorPos(996, 184); Start-Sleep -Milliseconds 600
    [K]::mouse_event(2, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 300
    for ($i = 1; $i -le 20; $i++) { [void][K]::SetCursorPos(996 + 2 * $i, 184); Start-Sleep -Milliseconds 50 }
    Start-Sleep -Milliseconds 300; [K]::mouse_event(4, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 500
    if ($p.LeftIndent -ne 0) { break }
  }
  Log ("RULER 左縮排 -> {0} 第{1}次{2}" -f $p.LeftIndent, $t, $(if ($p.LeftIndent -ne 0) { '' } else { ' ⚠ 沒拖到' }))
  $p.LeftIndent = 0; FocusWin $script:win; GoEnd; $stat.ruler++; Trig '拖尺規'
}
function Citation($o) {
  $tag = $o.tag; $res = "$($o.result)"
  $au = 'Unknown'; $yr = ''
  if ($res -match '\(?\s*(.+?),\s*(\d{4}|n\.d\.)') { $au = $Matches[1]; $yr = $Matches[2] }
  $have = $false; foreach ($s in $script:d.Bibliography.Sources) { if ($s.Tag -eq $tag) { $have = $true; break } }
  if (-not $have) {
    $e = { param($x) [Security.SecurityElement]::Escape($x) }
    $xml = "<b:Source xmlns:b=`"http://schemas.openxmlformats.org/officeDocument/2006/bibliography`"><b:Tag>$(& $e $tag)</b:Tag><b:SourceType>DocumentFromInternetSite</b:SourceType><b:Author><b:Author><b:Corporate>$(& $e $au)</b:Corporate></b:Author></b:Author><b:Title>$(& $e $au)</b:Title><b:Year>$yr</b:Year></b:Source>"
    $script:d.Bibliography.Sources.Add($xml)
  }
  [void]$script:sel.Fields.Add($script:sel.Range, -1, "CITATION $tag \l 1028 ", $false)
  GoEnd; $stat.citation++
}

try {
  Log "start ops=$($plan.Count) limit=$Limit"
  $script:w = New-Object -ComObject Word.Application; $script:w.Visible = $true
  $script:d = $script:w.Documents.Add(); $script:win = $script:d.Windows(1)
  $script:win.View.Type = 3; $script:win.DisplayRulers = $true; $script:win.WindowState = 1
  $script:sel = $script:w.Selection
  Start-Sleep 2; FocusWin $script:win
  if (-not (UseTip 'chewing' { $script:d.Content.Text })) { throw '切不到新酷音，不開始' }
  $t0 = Get-Date; $i = 0
  foreach ($o in $plan) {
    $i++; if ($Limit -and $i -gt $Limit) { break }
    switch ($o.op) {
      'style'     { $script:sel.Style = $script:d.Styles.Item($STY[$o.name]) }
      'para'      { Press 'return' }
      'pagebreak' { Press 'ctrl+return'; Trig '分頁' }
      'section'   { $script:sel.InsertBreak(2); $script:d.Sections($script:d.Sections.Count).Headers(1).LinkToPrevious = $false; Trig '分節' }
      'header'    {
        $script:win.ActivePane.View.SeekView = 9; Start-Sleep -Milliseconds 1000
        $script:inHeader = $true   # 不要 FocusWin：會讓 Word 跳回正文
        RunText $o.ops
        $script:inHeader = $false
        $script:win.ActivePane.View.SeekView = 0; Start-Sleep -Milliseconds 300; GoEnd; Trig '頁首'
      }
      'img'       { Img $o }
      'ruler'     { Ruler }
      'citation'  { Citation $o; Trig '引用' }
      'xref'      { [void]$script:sel.InsertCrossReference($o.label, 3, $o.idx); GoEnd; Trig '交互參照' }
      'caption'   {
        $script:sel.Style = $script:d.Styles.Item(-35)
        RunText @(@{ op = 'zh'; text = $o.label; n = 1; keys = $(if ($o.label -eq '圖') { 'w j 6 return' } else { '1 u l 3 return' }) })
        $script:sel.TypeText(' '); [void]$script:sel.Fields.Add($script:sel.Range, 12, "$($o.label) \* ARABIC", $false); GoEnd
        $script:sel.TypeText('　'); RunText $o.ops; Press 'return'; $stat.caption++; Trig '圖說'
      }
      'footnote'  {
        [void]$script:d.Footnotes.Add($script:sel.Range); Start-Sleep -Milliseconds 400
        RunText $o.ops; GoEnd; $stat.footnote++; Trig '註腳'
      }
      'table'     {
        $rows = $o.rows.Count; $cols = ($o.rows | ForEach-Object { $_.Count } | Measure-Object -Maximum).Maximum
        $t = $script:d.Tables.Add($script:sel.Range, $rows, $cols); $t.Borders.Enable = $true
        $t.Cell(1, 1).Select()
        for ($r = 0; $r -lt $rows; $r++) { for ($c = 0; $c -lt $cols; $c++) {
          if ($c -lt $o.rows[$r].Count) { RunText $o.rows[$r][$c] }
          if (-not ($r -eq $rows - 1 -and $c -eq $cols - 1)) { Press 'tab' }
        } }
        GoEnd; $stat.table++; Trig '表格'
      }
      'toc'       { $r = $script:d.Range(0, 0); [void]$script:d.TablesOfContents.Add($r); $script:d.TablesOfContents(1).Update(); Trig '目錄' }
      default     { RunText @($o) }
    }
    if ($i % 100 -eq 0) { Log ("進度 {0}/{1} 經輸入法中文 {2} 字 標點 {3} 警告 {4} 經過 {5:N0} 秒" -f $i, $plan.Count, $stat.zhChars, $stat.punct, $stat.warn, ((Get-Date) - $t0).TotalSeconds) }
  }
  $script:d.Fields.Update() | Out-Null
  Log ("完成 經輸入法中文 {0} 字（{1} 段）標點 {2} 英數段 {3} 圖 {4} 表 {5} 註腳 {6} 引用 {7} 圖說 {8} 拖尺規 {9} 警告 {10}" -f $stat.zhChars, $stat.zh, $stat.punct, $stat.ascii, $stat.img, $stat.table, $stat.footnote, $stat.citation, $stat.caption, $stat.ruler, $stat.warn)
} catch [Dead] { Log "DEAD $($_.Exception.Message)"; Log ("死前統計 經輸入法中文 {0} 字 標點 {1} 圖 {2} 表 {3} 拖尺規 {4}" -f $stat.zhChars, $stat.punct, $stat.img, $stat.table, $stat.ruler)
} catch { Log "ERROR 第 $i 個操作 $($o.op)：$_ @ $($_.InvocationInfo.ScriptLineNumber)" }
finally {
  try { $script:d.SaveAs2("$env:USERPROFILE\cjtest\$Name.docx"); Log "已存檔 $Name.docx" } catch { Log "存檔失敗 $_" }
  try { foreach ($x in @($script:w.Documents)) { $x.Saved = $true }; $script:w.Quit() } catch { }
  Start-Sleep 2
  Get-Process WINWORD -EA SilentlyContinue | ForEach-Object { Log "Word 沒關掉，強制結束 $($_.Id)"; $_.Kill() }
  Log 'end'
}
