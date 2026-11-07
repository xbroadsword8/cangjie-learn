$ProgressPreference='SilentlyContinue'
foreach ($a in 'x64','x86') { $f="$env:USERPROFILE\dl\vc_redist.$a.exe"
  Invoke-WebRequest "https://aka.ms/vs/17/release/vc_redist.$a.exe" -OutFile $f -UseBasicParsing
  $p = Start-Process $f -ArgumentList '/install /quiet /norestart' -Wait -PassThru; "$a exit $($p.ExitCode)" }
