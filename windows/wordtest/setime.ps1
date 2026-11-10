# setime.ps1 <InputTip>：把輸入法加進中文清單（若沒有）並設為預設；setime.ps1 -Restore 還原清單與預設
param($Tip, [switch]$Restore)
$chew = '0404:{13F2EF08-575C-4D8C-88E0-F67BB8052B84}{CE45F71D-CE79-41D1-967D-640B65A380E3}'
$l = Get-WinUserLanguageList
$zh = $l | Where-Object LanguageTag -eq 'zh-Hant-TW'
if ($Restore) {
  [void]$zh.InputMethodTips.Remove($chew); Set-WinUserLanguageList $l -Force
  Clear-WinDefaultInputMethodOverride 2>$null; if (Get-WinDefaultInputMethodOverride) { Set-WinDefaultInputMethodOverride -InputTip '' }
} else {
  if (-not $zh.InputMethodTips.Contains($Tip)) { $zh.InputMethodTips.Add($Tip); Set-WinUserLanguageList $l -Force }
  Set-WinDefaultInputMethodOverride -InputTip $Tip
}
[Console]::OutputEncoding = [Text.Encoding]::UTF8
(Get-WinUserLanguageList | Where-Object LanguageTag -eq 'zh-Hant-TW').InputMethodTips -join ','
'override=' + (Get-WinDefaultInputMethodOverride | Out-String).Trim()
