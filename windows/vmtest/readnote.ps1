# 在互動桌面跑：讀每個記事本的內容，寫 readnote.log
param($Out = "$env:USERPROFILE\readnote.log")
Add-Type @'
using System; using System.Text; using System.Runtime.InteropServices;
public class R { [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindowEx(IntPtr p, IntPtr a, string c, string w);
 [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr SendMessageTimeout(IntPtr h, uint m, IntPtr w, StringBuilder l, uint f, uint t, out IntPtr r); }
'@
$lines = foreach ($p in Get-Process notepad | sort StartTime) {
  $e = [R]::FindWindowEx($p.MainWindowHandle, [IntPtr]::Zero, 'Edit', $null)
  $sb = New-Object Text.StringBuilder 4096; $r = [IntPtr]::Zero
  $ok = [R]::SendMessageTimeout($e, 0x0D, [IntPtr]4096, $sb, 2, 3000, [ref]$r)
  "pid=$($p.Id) responded=$($ok -ne [IntPtr]::Zero) text=[$($sb.ToString())]"
}
$lines | Out-File $Out -Encoding utf8
