// 按鍵狀態機：Python cjlearn/composer.py 的逐行移植。鍵用 X keysym 名稱字串。
import Foundation

let RADICALS: [Character: String] = {
    let keys = Array("abcdefghijklmnopqrstuvwxyz")
    let vals = Array("日月金木水火土竹戈十大中一弓人心手口尸廿山女田難卜重")
    var d: [Character: String] = [:]
    for (k, v) in zip(keys, vals) { d[k] = String(v) }
    return d
}()

let CJK_PUNCT: [String: String] = [
    "comma": "，", "period": "。", "semicolon": "；", "colon": "：",
    "question": "？", "exclam": "！", "apostrophe": "、", "backslash": "、",
    "bracketleft": "「", "bracketright": "」", "braceleft": "『", "braceright": "』",
    "parenleft": "（", "parenright": "）", "less": "《", "greater": "》",
    "quotedbl": "＂", "slash": "／", "asciitilde": "～", "asciicircum": "……",
    "underscore": "——", "minus": "－", "at": "＠", "numbersign": "＃",
    "dollar": "＄", "percent": "％", "ampersand": "＆", "asterisk": "＊",
    "plus": "＋", "equal": "＝", "bar": "｜", "grave": "‵",
]
let ASCII_PUNCT: [String: String] = [
    "comma": ",", "period": ".", "semicolon": ";", "colon": ":", "question": "?",
    "exclam": "!", "apostrophe": "'", "quotedbl": "\"", "backslash": "\\", "slash": "/",
    "bracketleft": "[", "bracketright": "]", "braceleft": "{", "braceright": "}",
    "parenleft": "(", "parenright": ")", "less": "<", "greater": ">", "asciitilde": "~",
    "asciicircum": "^", "underscore": "_", "minus": "-", "at": "@", "numbersign": "#",
    "dollar": "$", "percent": "%", "ampersand": "&", "asterisk": "*", "plus": "+",
    "equal": "=", "bar": "|", "grave": "`",
]
// fullPunct 開啟時，中文模式不按 Ctrl 也出全形的鍵（其餘符號仍出半形）
let FULL_PUNCT_KEYS: Set<String> = [
    "comma", "period", "semicolon", "colon", "question", "exclam", "backslash",
    "bracketleft", "bracketright", "braceleft", "braceright",
    "parenleft", "parenright", "less", "greater",
]
let CONTEXT_BREAK: Set<String> = ["Return", "KP_Enter", "Tab", "Left", "Right", "Up", "Down", "Home", "End",
                                  "Page_Up", "Page_Down", "Delete", "Escape"]
let MAX_CODE = 5
let PAGE = 9

/// handled：是否吃掉此鍵；commit：要送出的文字。
struct ComposerResult {
    var handled: Bool
    var commit: String = ""
}

/// 單一碼點的鍵（對應 Python len(key)==1），回傳其碼點值。
private func single(_ key: String) -> UInt32? {
    let u = key.unicodeScalars
    guard u.count == 1 else { return nil }
    return u.first!.value
}

final class Composer {
    let model: Model
    var chinese = true
    var code = ""
    var cands: [Candidate] = []
    var page = 0
    var cursor = 0           // 頁內游標
    var ctx = ""             // 最近送出的中文字（上文）
    var clearOnError = true  // 打錯碼（沒有候選）按空白或數字鍵：清掉字碼
    var fullPunct = false    // 中文模式常用標點不按 Ctrl 也出全形（仿微軟倉頡）
    private var shiftAlone = false

    init(model: Model) { self.model = model }

    // --- 對外狀態 ---
    func preedit() -> String {
        var s = ""
        for c in code { s += RADICALS[c]! }
        return s
    }

    func pageCands() -> [Candidate] {
        let n = cands.count
        let s = min(page * PAGE, n)
        let e = min((page + 1) * PAGE, n)
        return Array(cands[s..<e])
    }

    func reset() {
        code = ""; cands = []; page = 0; cursor = 0
        ctx = ""
    }

    // --- 內部 ---
    private func refresh() {
        cands = model.candidates(code: code, ctx: ctx)
        page = 0; cursor = 0
    }

    private func clear() {
        code = ""; cands = []; page = 0; cursor = 0
    }

    private func pick(_ idxInPage: Int? = nil) -> String {
        let pg = pageCands()
        let i = idxInPage ?? cursor
        if i >= pg.count { return "" }
        let ch = pg[i].ch
        model.learn(ch, prev: ctx, corrected: (page * PAGE + i) > 0)
        ctx = tailScalars(ctx + ch, 3)
        clear()
        return ch
    }

    private func flush() -> String {
        if code.isEmpty { return "" }
        if cands.isEmpty {
            clear()
            return ""
        }
        return pick(0)
    }

    // --- 主入口 ---
    func process(_ key: String, ctrl: Bool = false, shift: Bool = false, alt: Bool = false,
                 release: Bool = false) -> ComposerResult {
        if key == "Shift_L" || key == "Shift_R" {
            if !release {
                shiftAlone = !(ctrl || alt)
                return ComposerResult(handled: false)
            }
            if shiftAlone {
                shiftAlone = false
                let commit = code.isEmpty ? "" : code
                clear()
                chinese = !chinese
                ctx = ""
                return ComposerResult(handled: !commit.isEmpty, commit: commit)
            }
            return ComposerResult(handled: false)
        }
        if release { return ComposerResult(handled: false) }
        shiftAlone = false

        if ctrl && !alt, let p = CJK_PUNCT[key] {
            let out = flush() + p
            ctx = ""
            return ComposerResult(handled: true, commit: out)
        }

        if !chinese {
            if CONTEXT_BREAK.contains(key) { ctx = "" }
            return ComposerResult(handled: false)
        }

        if ctrl || alt { return ComposerResult(handled: false) }

        // 組字
        if let v = single(key), v >= 0x61 && v <= 0x7A {
            if code.count >= MAX_CODE { return ComposerResult(handled: true) }
            code += key
            refresh()
            return ComposerResult(handled: true)
        }

        if fullPunct && FULL_PUNCT_KEYS.contains(key), let p = CJK_PUNCT[key] {
            let out = flush() + p
            ctx = ""
            return ComposerResult(handled: true, commit: out)
        }

        if !code.isEmpty { return processComposing(key) }

        // 沒有組字中
        if key == "BackSpace" {
            if !ctx.isEmpty {
                var u = Array(ctx.unicodeScalars); u.removeLast()
                var v = String.UnicodeScalarView(); v.append(contentsOf: u)
                ctx = String(v)
            }
        } else if CONTEXT_BREAK.contains(key) || key == "space" || ASCII_PUNCT[key] != nil {
            ctx = ""
        } else if let v = single(key), v >= 0x41 && v <= 0x5A {
            ctx = ""
        }
        return ComposerResult(handled: false)
    }

    private func processComposing(_ key: String) -> ComposerResult {
        let pg = pageCands()
        if cands.isEmpty && clearOnError, key == "space" || (single(key).map { $0 >= 0x31 && $0 <= 0x39 } ?? false) {
            clear()
            return ComposerResult(handled: true)
        }
        if key == "space" {
            return ComposerResult(handled: true, commit: pick())
        }
        if let v = single(key), v >= 0x31 && v <= 0x39 {
            let i = Int(v) - 0x31
            if i < pg.count {
                return ComposerResult(handled: true, commit: pick(i))
            }
            return ComposerResult(handled: true)
        }
        if key == "BackSpace" {
            code.removeLast()
            if !code.isEmpty { refresh() } else { clear() }
            return ComposerResult(handled: true)
        }
        if key == "Escape" {
            clear()
            return ComposerResult(handled: true)
        }
        if key == "Return" || key == "KP_Enter" {
            let raw = code
            clear()
            ctx = ""
            return ComposerResult(handled: true, commit: raw)
        }
        if key == "Page_Down" || key == "equal" || key == "KP_Page_Down" {
            if (page + 1) * PAGE < cands.count {
                page += 1
                cursor = 0
            }
            return ComposerResult(handled: true)
        }
        if key == "Page_Up" || key == "minus" || key == "KP_Page_Up" {
            if page > 0 {
                page -= 1
                cursor = 0
            }
            return ComposerResult(handled: true)
        }
        if key == "Down" || key == "Right" {
            if cursor + 1 < pg.count {
                cursor += 1
            } else if (page + 1) * PAGE < cands.count {
                page += 1
                cursor = 0
            }
            return ComposerResult(handled: true)
        }
        if key == "Up" || key == "Left" {
            if cursor > 0 {
                cursor -= 1
            } else if page > 0 {
                page -= 1
                cursor = PAGE - 1
            }
            return ComposerResult(handled: true)
        }
        if let p = ASCII_PUNCT[key] {
            let out = flush() + p
            ctx = ""
            return ComposerResult(handled: true, commit: out)
        }
        if let v = single(key), v >= 0x41 && v <= 0x5A {
            let out = flush() + key
            ctx = ""
            return ComposerResult(handled: true, commit: out)
        }
        let out = flush()
        ctx = ""
        return ComposerResult(handled: false, commit: out)
    }
}
