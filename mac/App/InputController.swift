import Cocoa
import InputMethodKit

private let radicals = Array("日月金木水火土竹戈十大中一弓人心手口尸廿山女田難卜重")

private func radicalString(_ code: Substring) -> String {
    String(code.compactMap { c -> Character? in
        guard let a = c.asciiValue, a >= 97, a <= 122 else { return nil }
        return radicals[Int(a - 97)]
    })
}

/// 所有輸入框共用一份模型與學習資料（跟 Linux／Windows 版一樣）。
/// 測試可用 CJLEARN_MODEL_DB／CJLEARN_USER_DB 覆寫路徑。
private let userDBPath: String = ProcessInfo.processInfo.environment["CJLEARN_USER_DB"]
    ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("CangjieLearn/user.db").path

let sharedModel: Model = {
    let env = ProcessInfo.processInfo.environment
    let userDB = userDBPath
    let modelDB = env["CJLEARN_MODEL_DB"] ?? Bundle.main.path(forResource: "model", ofType: "db")!
    return try! Model(modelDB: modelDB, userDB: userDB)
}()

let candidateWindow = CandidateWindow()
let dataDir = (userDBPath as NSString).deletingLastPathComponent
let peers = Sync.PeerWatcher(dataDir: dataDir)   // 其他電腦的學習資料（sync.py 同步到 sync/）

/// 使用者選項：學習資料旁的 settings.json，格式與 Linux／Windows 版相同（cjlearn/settings.py）。
final class Settings {
    static let shared = Settings()
    let path = dataDir + "/settings.json"
    var clearOnError = true   // 打錯碼（沒有候選）按空白或數字鍵：清掉字碼

    init() {
        if let data = FileManager.default.contents(atPath: path),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let n = obj["clear_on_error"] as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() {
            clearOnError = n.boolValue   // 只認 true／false，跟 Python 版一樣忽略型別不對的值
        }
    }

    /// 重讀再改：sync.py 會寫 sync_name 等其他設定，不能整份蓋掉
    func save() {
        var obj: [String: Any] = [:]
        if let data = FileManager.default.contents(atPath: path),
           let old = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] { obj = old }
        obj["clear_on_error"] = clearOnError
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted]) else { return }
        try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                                 withIntermediateDirectories: true)
        try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}

@objc(CangjieLearnInputController)
final class CangjieLearnInputController: IMKInputController {
    private lazy var comp = Composer(model: sharedModel)
    private var hasMarked = false
    @objc var isChinese: Bool { comp.chinese }   // 給外殼測試讀

    override func recognizedEvents(_ sender: Any!) -> Int {
        Int(NSEvent.EventTypeMask.keyDown.rawValue | NSEvent.EventTypeMask.flagsChanged.rawValue)
    }

    override func activateServer(_ sender: Any!) {
        super.activateServer(sender)
        comp.clearOnError = Settings.shared.clearOnError
        peers.poll(sharedModel)
        comp.reset()
        hasMarked = false
    }

    /// 選單列輸入法圖示的選單
    override func menu() -> NSMenu! {
        let menu = NSMenu()
        let item = NSMenuItem(title: "打錯碼按空白清掉", action: #selector(toggleClearOnError(_:)), keyEquivalent: "")
        item.state = Settings.shared.clearOnError ? .on : .off
        menu.addItem(item)
        let status = Sync.statusText(dataDir)
        if !status.isEmpty {
            let s = NSMenuItem(title: status, action: nil, keyEquivalent: "")
            s.isEnabled = false
            menu.addItem(s)
        }
        return menu
    }

    @objc func toggleClearOnError(_ sender: Any?) {
        Settings.shared.clearOnError.toggle()
        Settings.shared.save()
        comp.clearOnError = Settings.shared.clearOnError
    }

    override func deactivateServer(_ sender: Any!) {
        clearComposition(sender)
        candidateWindow.hide()
        super.deactivateServer(sender)
    }

    /// 應用程式要求結束組字（點別處、切視窗）：丟掉打到一半的碼並斷開上文，跟 Linux 版 focus_out 一樣。
    override func commitComposition(_ sender: Any!) {
        clearComposition(sender)
    }

    private func clearComposition(_ sender: Any!) {
        comp.reset()
        if hasMarked, let client = sender as? IMKTextInput {
            client.setMarkedText("", selectionRange: NSRange(location: 0, length: 0),
                                 replacementRange: NSRange(location: NSNotFound, length: 0))
        }
        hasMarked = false
        candidateWindow.hide()
    }

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event = event, let client = sender as? IMKTextInput else { return false }
        let flags = event.modifierFlags
        let ctrl = flags.contains(.control), alt = flags.contains(.option), shift = flags.contains(.shift)

        if event.type == .flagsChanged {
            guard let (name, down) = modifierChange(keyCode: event.keyCode, rawFlags: flags.rawValue) else { return false }
            let wasChinese = comp.chinese
            let r = comp.process(name, ctrl: ctrl, shift: shift, alt: alt, release: !down)
            if !r.commit.isEmpty { insert(r.commit, client) }
            render(client)
            if comp.chinese != wasChinese { candidateWindow.flash(comp.chinese ? "中" : "英", caret: caretRect(client)) }
            return false    // 修飾鍵一律讓應用程式也看到
        }

        guard event.type == .keyDown else { return false }
        if flags.contains(.command) {   // Cmd 快捷鍵交給應用程式；打到一半先結束組字
            if !comp.code.isEmpty { clearComposition(sender) }
            return false
        }
        guard let name = keysymName(keyCode: event.keyCode, shift: shift, ctrl: ctrl,
                                    caps: flags.contains(.capsLock)) else { return false }
        let r = comp.process(name, ctrl: ctrl, shift: shift, alt: alt, release: false)
        if !r.commit.isEmpty { insert(r.commit, client) }
        render(client)
        return r.handled
    }

    private func insert(_ s: String, _ client: IMKTextInput) {
        client.insertText(s, replacementRange: NSRange(location: NSNotFound, length: 0))
        hasMarked = false   // insertText 會取代組字區
    }

    private func render(_ client: IMKTextInput) {
        let pre = comp.preedit()
        if pre.isEmpty {
            if hasMarked {
                client.setMarkedText("", selectionRange: NSRange(location: 0, length: 0),
                                     replacementRange: NSRange(location: NSNotFound, length: 0))
                hasMarked = false
            }
            candidateWindow.hide()
            return
        }
        let marked = NSAttributedString(string: pre, attributes: [.underlineStyle: NSUnderlineStyle.single.rawValue])
        client.setMarkedText(marked, selectionRange: NSRange(location: (pre as NSString).length, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
        hasMarked = true
        let code = comp.code
        let items = comp.pageCands().map { c -> (String, String) in
            // 補完候選附上還沒打的部件，順便練碼
            (c.ch, c.exact ? "" : radicalString(c.code.dropFirst(code.count)))
        }
        if items.isEmpty { candidateWindow.hide() } else {
            candidateWindow.show(items: items, cursor: comp.cursor, caret: caretRect(client))
        }
    }

    private func caretRect(_ client: IMKTextInput) -> NSRect {
        var rect = NSRect.zero
        client.attributes(forCharacterIndex: 0, lineHeightRectangle: &rect)
        return rect
    }
}
