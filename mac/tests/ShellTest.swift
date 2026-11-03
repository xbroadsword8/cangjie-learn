// 外殼測試：假的輸入框（IMKTextInput）＋合成的 NSEvent，直接驅動 CangjieLearnInputController。不需要畫面。
// 編譯：swiftc -swift-version 5 mac/Core/*.swift mac/App/{KeyMap,CandidateWindow,InputController}.swift mac/tests/ShellTest.swift \
//        -framework Cocoa -framework InputMethodKit -o shelltest
// 執行：CJLEARN_NO_UI=1 CJLEARN_MODEL_DB=data/model.db CJLEARN_USER_DB=<暫存檔> ./shelltest
import Cocoa
import InputMethodKit

final class FakeClient: NSObject, IMKTextInput {
    var text = ""          // 已送出的字
    var marked = ""        // 組字區
    func insertText(_ string: Any!, replacementRange: NSRange) {
        text += (string as? String) ?? (string as? NSAttributedString)?.string ?? ""
        marked = ""
    }
    func setMarkedText(_ string: Any!, selectionRange: NSRange, replacementRange: NSRange) {
        marked = (string as? String) ?? (string as? NSAttributedString)?.string ?? ""
    }
    func selectedRange() -> NSRange { NSRange(location: text.utf16.count, length: 0) }
    func markedRange() -> NSRange { NSRange(location: NSNotFound, length: 0) }
    func attributedSubstring(from range: NSRange) -> NSAttributedString! { NSAttributedString(string: "") }
    func length() -> Int { text.utf16.count }
    func characterIndex(for point: NSPoint, tracking mappingMode: IMKLocationToOffsetMappingMode,
                        inMarkedRange: UnsafeMutablePointer<ObjCBool>!) -> Int { 0 }
    func attributes(forCharacterIndex index: Int, lineHeightRectangle: UnsafeMutablePointer<NSRect>!) -> [AnyHashable: Any]! {
        lineHeightRectangle?.pointee = NSRect(x: 100, y: 500, width: 1, height: 18)
        return [:]
    }
    func validAttributesForMarkedText() -> [Any]! { [] }
    func overrideKeyboard(withKeyboardNamed keyboardUniqueName: String!) {}
    func selectMode(_ modeIdentifier: String!) {}
    func supportsUnicode() -> Bool { true }
    func bundleIdentifier() -> String! { "test.fake" }
    func windowLevel() -> CGWindowLevel { 0 }
    func supportsProperty(_ property: TSMDocumentPropertyTag) -> Bool { false }
    func uniqueClientIdentifierString() -> String! { "fake" }
    func string(from range: NSRange, actualRange: NSRangePointer!) -> String! { "" }
    func firstRect(forCharacterRange aRange: NSRange, actualRange: NSRangePointer!) -> NSRect { .zero }
}

// kVK_* 與裝置旗標
let K: [Character: UInt16] = ["a": 0, "b": 11, "c": 8, "d": 2, "e": 14, "f": 3, "g": 5, "h": 4, "i": 34, "j": 38,
    "k": 40, "l": 37, "m": 46, "n": 45, "o": 31, "p": 35, "q": 12, "r": 15, "s": 1, "t": 17, "u": 32, "v": 9,
    "w": 13, "x": 7, "y": 16, "z": 6, " ": 49, ",": 43, ".": 47, "1": 18, "2": 19, "3": 20, ";": 41, "[": 33]
let kShiftL: UInt16 = 56, kCtrlL: UInt16 = 59, kCmd: UInt16 = 55, kBack: UInt16 = 51, kEsc: UInt16 = 53, kReturn: UInt16 = 36
let fShift: UInt = 0x20000 | 0x02, fCtrl: UInt = 0x40000 | 0x01, fCmd: UInt = 0x100000 | 0x08

final class Driver {
    let ctl: CangjieLearnInputController
    let client = FakeClient()
    var flags: UInt = 0x100     // NX_NONCOALSESCEDMASK
    init() {
        ctl = CangjieLearnInputController(server: nil, delegate: nil, client: nil)
        ctl.activateServer(client)
    }
    @discardableResult func key(_ code: UInt16) -> Bool {
        let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: NSEvent.ModifierFlags(rawValue: flags),
                                 timestamp: 0, windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
                                 isARepeat: false, keyCode: code)!
        return ctl.handle(e, client: client)
    }
    func mod(_ code: UInt16, _ bits: UInt, down: Bool) {
        flags = down ? flags | bits : flags & ~bits
        let e = NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: NSEvent.ModifierFlags(rawValue: flags),
                                 timestamp: 0, windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
                                 isARepeat: false, keyCode: code)!
        _ = ctl.handle(e, client: client)
    }
    func type(_ s: String) { for c in s { key(K[c]!) } }
    func with(_ code: UInt16, _ bits: UInt, _ body: () -> Void) { mod(code, bits, down: true); body(); mod(code, bits, down: false) }
}

var failed = 0
func check(_ name: String, _ got: Any, _ want: Any) {
    let ok = "\(got)" == "\(want)"
    if !ok { failed += 1 }
    print(ok ? "PASS" : "FAIL", name, ok ? "" : "got=\(got) want=\(want)")
}

var d = Driver()
d.type("hq")
check("組字區顯示字根", d.client.marked, "竹手")
check("候選窗有內容", !candidateWindow.shown.isEmpty, true)
d.type("i ")
check("空白送出第一候選", d.client.text, "我")
check("送出後組字區清空", d.client.marked, "")
check("送出後候選窗關閉", candidateWindow.shown.isEmpty, true)

d.with(kCtrlL, fCtrl) { d.key(K[","]!) }
check("Ctrl+, 出全形逗號", d.client.text, "我，")
let handledComma = d.key(K[","]!)
check("一般逗號交給應用程式（半形）", handledComma, false)
d.with(kShiftL, fShift) { d.with(kCtrlL, fCtrl) { d.key(K[";"]!) } }
check("Ctrl+Shift+; 出全形冒號", d.client.text, "我，：")

d = Driver()
d.with(kShiftL, fShift) {}
check("單按 Shift 切英文", sharedModelChinese(d), false)
check("切換時顯示「英」", candidateWindow.flashed, "英")
check("英文模式字母交給應用程式", d.key(K["a"]!), false)
d.with(kShiftL, fShift) {}
check("再按 Shift 切回中文", sharedModelChinese(d), true)
d.with(kShiftL, fShift) { d.key(K["a"]!) }
check("Shift+字母不切換", sharedModelChinese(d), true)

d = Driver()
d.type("hq")
d.with(kShiftL, fShift) {}
check("打一半切英文：送出已打字母", d.client.text, "hq")

d = Driver()
d.type("hq")
d.key(kBack)
check("BackSpace 刪一碼", d.client.marked, "竹")
d.key(kEsc)
check("Esc 取消組字", d.client.marked + d.client.text, "")
d.type("hqi")
d.mod(kCmd, fCmd, down: true)
check("Cmd 快捷鍵交給應用程式", d.key(K["c"]!), false)
d.mod(kCmd, fCmd, down: false)
check("Cmd 時結束組字", d.client.marked, "")

d = Driver()
d.type("tcp")
let pageItems = candidateWindow.shown.map { $0.0 }
d.key(K["2"]!)
check("數字鍵選第 2 個候選", d.client.text, pageItems.count > 1 ? pageItems[1] : "?")

d = Driver()
d.type("qqqq")
check("空白被吃掉不外漏", d.key(K[" "]!), true)
check("打錯碼按空白清掉", d.client.marked + d.client.text, "")
d.type("hqi ")
check("清掉後照常打字", d.client.text, "我")
let menu = d.ctl.menu()!
check("選單項目預設打勾", menu.items[0].state == .on, true)
d.ctl.perform(menu.items[0].action!, with: menu.items[0])
check("選單關掉後打錯碼停住", { d.type("qqqq "); return d.client.marked }(), "手手手手")
check("選項存檔", (try? String(contentsOfFile: Settings.shared.path, encoding: .utf8))?.contains("false") ?? false, true)
check("關掉後選單不打勾", d.ctl.menu()!.items[0].state == .off, true)
d.ctl.perform(menu.items[0].action!, with: menu.items[0])

print(failed == 0 ? "ALL PASSED" : "FAILED \(failed)")
exit(failed == 0 ? 0 : 1)

func sharedModelChinese(_ d: Driver) -> Bool { d.ctl.value(forKey: "isChinese") as! Bool }
