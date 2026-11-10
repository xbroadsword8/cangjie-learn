# 共用：模擬按鍵、前景、紀錄（dot-source 使用：. kb.ps1）
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type @'
using System; using System.Runtime.InteropServices;
public class K {
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  [DllImport("user32.dll")] public static extern uint MapVirtualKey(uint code, uint type);
  [DllImport("user32.dll")] public static extern short VkKeyScan(char c);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int x, int y, uint d, UIntPtr e);
  public static int Delay = 60;
  public static void Down(byte vk) { keybd_event(vk, (byte)MapVirtualKey(vk, 0), 0, UIntPtr.Zero); }
  public static void Up(byte vk) { keybd_event(vk, (byte)MapVirtualKey(vk, 0), 2, UIntPtr.Zero); }
  public static void Tap(byte vk) { Down(vk); System.Threading.Thread.Sleep(20); Up(vk); System.Threading.Thread.Sleep(Delay); }
  public static void Combo(byte mod, byte vk) { Down(mod); System.Threading.Thread.Sleep(20); Tap(vk); Up(mod); System.Threading.Thread.Sleep(Delay); }
  // 英文模式下打 ASCII：用 VkKeyScan 找鍵與 Shift
  public static void Ascii(string s) {
    foreach (char c in s) {
      short r = VkKeyScan(c); if (r == -1) continue;
      byte vk = (byte)(r & 0xff); bool sh = (r & 0x100) != 0;
      if (sh) Combo(0x10, vk); else Tap(vk);
    }
  }
}
'@
function Log($m) { "$(Get-Date -Format HH:mm:ss.fff) $m" | Out-File $script:Out -Append -Encoding utf8 }
function FocusWin($win) {
  $win.Activate(); [void][K]::SetForegroundWindow([IntPtr]$win.Hwnd); Start-Sleep -Milliseconds 400
}
# 按鍵規格：'a'、'shift+oem_comma'、'ctrl+x'、'vk:0x65'
$script:VKN = @{ space=0x20; return=0x0D; escape=0x1B; tab=0x09; back=0x08; shift=0x10; ctrl=0x11; alt=0x12; lwin=0x5B
  oem_comma=0xBC; oem_period=0xBE; oem_1=0xBA; oem_2=0xBF; oem_3=0xC0; oem_4=0xDB; oem_5=0xDC; oem_6=0xDD; oem_7=0xDE; oem_minus=0xBD; oem_plus=0xBB
  num5=0x65; up=0x26; down=0x28; left=0x25; right=0x27; home=0x24; end=0x23 }
function VkOf($k) { if ($script:VKN.ContainsKey($k)) { $script:VKN[$k] } elseif ($k -match '^[a-z]$') { [int][char]$k.ToUpper() } elseif ($k -match '^[0-9]$') { [int][char]$k } else { throw "未知按鍵 $k" } }
function Press($spec) {
  foreach ($k in $spec.Split(' ')) {
    if (-not $k) { continue }
    $parts = $k.Split('+')
    if ($parts.Count -eq 3) { $m1 = [byte](VkOf $parts[0]); $m2 = [byte](VkOf $parts[1]); [K]::Down($m1); [K]::Down($m2); Start-Sleep -Milliseconds 20; [K]::Tap([byte](VkOf $parts[2])); [K]::Up($m2); [K]::Up($m1); Start-Sleep -Milliseconds ([K]::Delay) }
    elseif ($parts.Count -eq 2) { [K]::Combo([byte](VkOf $parts[0]), [byte](VkOf $parts[1])) } else { [K]::Tap([byte](VkOf $k)) }
  }
}
# 直接切換整個工作階段的 TSF 輸入法（不靠「預設輸入法」，那個對已登入的工作階段不一定生效）
Add-Type @'
using System; using System.Runtime.InteropServices;
[ComImport, Guid("71C6E74C-0F28-11D8-A82A-00065B84435C"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface ITfInputProcessorProfileMgr {
  [PreserveSig] int ActivateProfile(uint type, ushort langid, ref Guid clsid, ref Guid profile, IntPtr hkl, uint flags);
}
public static class Tip {
  public static int Activate(string clsid, string profile) {
    var t = Type.GetTypeFromCLSID(new Guid("33C53A50-F456-4884-B049-85FD643ECFED"));
    var m = (ITfInputProcessorProfileMgr)Activator.CreateInstance(t);
    Guid c = new Guid(clsid), p = new Guid(profile);
    return m.ActivateProfile(1, 0x0404, ref c, ref p, IntPtr.Zero, 0x20000000 | 0x1);   // TF_IPPMF_FORSESSION | ENABLEPROFILE
  }
}
'@
$script:TIPS = @{
  chewing = @('{13F2EF08-575C-4D8C-88E0-F67BB8052B84}', '{CE45F71D-CE79-41D1-967D-640B65A380E3}', 'j i 3 return')
  cjlearn = @('{35F67E9D-A54D-4177-9697-8B0AB71A9E04}', '{42D1BA3B-DC86-44CE-AA0B-29BE3392897F}', 'h q i space')
}
# 切到指定輸入法並在目前游標處打一個「我」確認，確認後刪掉；回傳是否成功
function UseTip($name, $getText) {
  $t = $script:TIPS[$name]
  for ($try = 1; $try -le 3; $try++) {
    $hr = [Tip]::Activate($t[0], $t[1]); Start-Sleep -Milliseconds 800
    $b = & $getText; Press $t[2]; Start-Sleep -Milliseconds 500; $a = & $getText
    $new = if ($a.Length -gt $b.Length) { $a.Substring($b.Length - 1, $a.Length - $b.Length) } else { '' }
    for ($k = 0; $k -lt ($a.Length - $b.Length); $k++) { Press 'back' }
    Log ("TIP {0} hr=0x{1:X} 第{2}次 測試打出 [{3}]" -f $name, $hr, $try, ($new -replace "`r", '⏎'))
    if ($new -match '我') { return $true }
    Press 'escape'
  }
  return $false
}
