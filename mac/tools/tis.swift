// 向系統註冊／啟用／停用輸入法。用法：tis register <App 路徑> | tis disable | tis status
import Carbon
import Foundation

let sourceID = "com.xmac.inputmethod.CangjieLearn"
let args = CommandLine.arguments

func sources() -> [TISInputSource] {
    let filter = [kTISPropertyInputSourceID as String: sourceID] as CFDictionary
    return (TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource]) ?? []
}

func prop(_ s: TISInputSource, _ key: CFString) -> Bool {
    guard let p = TISGetInputSourceProperty(s, key) else { return false }
    return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(p).takeUnretainedValue())
}

switch args.count > 1 ? args[1] : "status" {
case "register":
    let st = TISRegisterInputSource(URL(fileURLWithPath: args[2]) as CFURL)
    print("register:", st)
    for s in sources() { print("enable:", TISEnableInputSource(s)) }
case "disable":
    for s in sources() { print("disable:", TISDisableInputSource(s)) }
default:
    let list = sources()
    print("found:", list.count)
    for s in list { print("enabled:", prop(s, kTISPropertyInputSourceIsEnabled), "selectable:", prop(s, kTISPropertyInputSourceIsSelectCapable)) }
}
