$H = $env:USERPROFILE
& "$H\runi.ps1" o1 'C:\Program Files\Google\Chrome\Application\chrome.exe' '--no-first-run https://www.google.com'
& "$H\runi.ps1" o2 'C:\Program Files\Mozilla Firefox\firefox.exe' 'https://zh.wikipedia.org'
& "$H\runi.ps1" o3 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe' '--no-first-run https://www.bing.com'
& "$H\runi.ps1" o5 explorer.exe $H
Start-Sleep 5
& "$H\runi.ps1" o4 notepad.exe
