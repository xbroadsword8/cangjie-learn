Set-WinSystemLocale zh-TW
Set-Culture zh-TW
Set-WinHomeLocation 0xED
$l = New-WinUserLanguageList zh-TW; $l.Add('en-US'); Set-WinUserLanguageList $l -Force
Get-WinUserLanguageList | % { "$($_.LanguageTag): $($_.InputMethodTips -join ',')" }
