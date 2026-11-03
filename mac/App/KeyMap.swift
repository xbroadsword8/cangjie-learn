// macOS 實體鍵位碼（kVK_*，美式 ANSI 位置）→ X keysym 名稱，讓核心 Composer 與 Linux／Windows 版共用同一套按鍵名稱。
// 用鍵位碼而不是 characters，切換鍵盤配置（ABC、Dvorak…）也不影響倉頡字根位置。

private let letters: [UInt16: Character] = [
    0: "a", 11: "b", 8: "c", 2: "d", 14: "e", 3: "f", 5: "g", 4: "h", 34: "i", 38: "j", 40: "k", 37: "l", 46: "m",
    45: "n", 31: "o", 35: "p", 12: "q", 15: "r", 1: "s", 17: "t", 32: "u", 9: "v", 13: "w", 7: "x", 16: "y", 6: "z",
]
private let digits: [UInt16: Int] = [29: 0, 18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9]
private let keypad: [UInt16: Int] = [82: 0, 83: 1, 84: 2, 85: 3, 86: 4, 87: 5, 88: 6, 89: 7, 91: 8, 92: 9]
private let shiftedDigits = ["parenright", "exclam", "at", "numbersign", "dollar", "percent",
                             "asciicircum", "ampersand", "asterisk", "parenleft"]
// 標點鍵：(不按 Shift, 按 Shift)
private let punct: [UInt16: (String, String)] = [
    41: ("semicolon", "colon"), 24: ("equal", "plus"), 43: ("comma", "less"), 27: ("minus", "underscore"),
    47: ("period", "greater"), 44: ("slash", "question"), 50: ("grave", "asciitilde"),
    33: ("bracketleft", "braceleft"), 42: ("backslash", "bar"), 30: ("bracketright", "braceright"),
    39: ("apostrophe", "quotedbl"),
]
private let special: [UInt16: String] = [
    51: "BackSpace", 48: "Tab", 36: "Return", 76: "KP_Enter", 53: "Escape", 49: "space",
    116: "Page_Up", 121: "Page_Down", 119: "End", 115: "Home",
    123: "Left", 126: "Up", 124: "Right", 125: "Down", 117: "Delete",
]

/// 一般按鍵（keyDown）。認不得回傳 nil，交給應用程式。
func keysymName(keyCode: UInt16, shift: Bool, ctrl: Bool, caps: Bool) -> String? {
    if let s = special[keyCode] { return s }
    if let c = letters[keyCode] {
        if ctrl { return String(c) }
        return shift != caps ? String(c).uppercased() : String(c)
    }
    if let d = digits[keyCode] { return shift ? shiftedDigits[d] : String(d) }
    if let d = keypad[keyCode] { return String(d) }
    if let p = punct[keyCode] { return shift ? p.1 : p.0 }
    return nil
}

/// 修飾鍵（flagsChanged）。用裝置相關旗標分辨左右鍵與按下／放開。
/// 旗標值取自 IOKit 的 NX_DEVICE*KEYMASK。
private let modifierBits: [UInt16: (String, UInt)] = [
    56: ("Shift_L", 0x02), 60: ("Shift_R", 0x04),
    59: ("Control_L", 0x01), 62: ("Control_R", 0x2000),
    58: ("Alt_L", 0x20), 61: ("Alt_R", 0x40),
    55: ("Super_L", 0x08), 54: ("Super_R", 0x10),
]

func modifierChange(keyCode: UInt16, rawFlags: UInt) -> (name: String, down: Bool)? {
    guard let (name, bit) = modifierBits[keyCode] else { return nil }
    return (name, rawFlags & bit != 0)
}
