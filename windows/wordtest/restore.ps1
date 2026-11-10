# 輸入法清單恢復測試前的順序（2026-11-09 22:2x 記錄的 baseline）
$order = '0404:{B115690A-EA02-48D5-A231-E3578D2FDF80}{B2F9C502-1742-11D4-9790-0080C882687E}',
         '0404:{35F67E9D-A54D-4177-9697-8B0AB71A9E04}{F828D2DC-81BE-466E-9CFE-24BB03172693}',
         '0404:{35F67E9D-A54D-4177-9697-8B0AB71A9E04}{42D1BA3B-DC86-44CE-AA0B-29BE3392897F}'
$l = Get-WinUserLanguageList
$zh = $l | Where-Object LanguageTag -eq 'zh-Hant-TW'
$zh.InputMethodTips.Clear(); foreach ($t in $order) { $zh.InputMethodTips.Add($t) }
Set-WinUserLanguageList $l -Force
