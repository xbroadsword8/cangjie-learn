$p = Start-Process "$env:USERPROFILE\pime-setup.exe" -ArgumentList '/S' -Wait -PassThru; "pime exit $($p.ExitCode)"
Test-Path 'C:\Program Files (x86)\PIME\python\server.py'
