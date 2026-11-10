//! Windows 虛擬鍵碼（VK）→ X keysym 名稱（對應 cjlearn 的 windows/pime/cjlearn/keymap.py，美式鍵盤）。
//! 純函式、不依賴 Windows API，可在 Linux 測。
pub const VK_BACK: u32 = 0x08;
pub const VK_TAB: u32 = 0x09;
pub const VK_RETURN: u32 = 0x0D;
pub const VK_SHIFT: u32 = 0x10;
pub const VK_CONTROL: u32 = 0x11;
pub const VK_MENU: u32 = 0x12;
pub const VK_CAPITAL: u32 = 0x14;
pub const VK_ESCAPE: u32 = 0x1B;
pub const VK_SPACE: u32 = 0x20;
pub const VK_PRIOR: u32 = 0x21;
pub const VK_NEXT: u32 = 0x22;
pub const VK_END: u32 = 0x23;
pub const VK_HOME: u32 = 0x24;
pub const VK_LEFT: u32 = 0x25;
pub const VK_UP: u32 = 0x26;
pub const VK_RIGHT: u32 = 0x27;
pub const VK_DOWN: u32 = 0x28;
pub const VK_DELETE: u32 = 0x2E;
pub const VK_LWIN: u32 = 0x5B;
pub const VK_RWIN: u32 = 0x5C;
pub const VK_NUMPAD0: u32 = 0x60;
pub const VK_NUMPAD9: u32 = 0x69;
pub const VK_LSHIFT: u32 = 0xA0;
pub const VK_RSHIFT: u32 = 0xA1;
pub const VK_LCONTROL: u32 = 0xA2;
pub const VK_RCONTROL: u32 = 0xA3;
pub const VK_LMENU: u32 = 0xA4;
pub const VK_RMENU: u32 = 0xA5;

const LOWER: [&str; 26] = [
    "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m",
    "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z",
];
const UPPER: [&str; 26] = [
    "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M",
    "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z",
];
const DIGITS: [&str; 10] = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"];
const SHIFTED_DIGITS: [&str; 10] = [
    "parenright", "exclam", "at", "numbersign", "dollar", "percent",
    "asciicircum", "ampersand", "asterisk", "parenleft",
];

fn special(vk: u32) -> Option<&'static str> {
    Some(match vk {
        VK_BACK => "BackSpace", VK_TAB => "Tab", VK_RETURN => "Return", VK_ESCAPE => "Escape",
        VK_SPACE => "space", VK_PRIOR => "Page_Up", VK_NEXT => "Page_Down", VK_END => "End",
        VK_HOME => "Home", VK_LEFT => "Left", VK_UP => "Up", VK_RIGHT => "Right", VK_DOWN => "Down",
        VK_DELETE => "Delete",
        VK_SHIFT | VK_LSHIFT => "Shift_L", VK_RSHIFT => "Shift_R",
        VK_CONTROL | VK_LCONTROL => "Control_L", VK_RCONTROL => "Control_R",
        VK_MENU | VK_LMENU => "Alt_L", VK_RMENU => "Alt_R", VK_CAPITAL => "Caps_Lock",
        _ => return None,
    })
}

/// 美式鍵盤標點鍵：(不按 Shift, 按 Shift)
fn oem(vk: u32) -> Option<(&'static str, &'static str)> {
    Some(match vk {
        0xBA => ("semicolon", "colon"), 0xBB => ("equal", "plus"), 0xBC => ("comma", "less"),
        0xBD => ("minus", "underscore"), 0xBE => ("period", "greater"), 0xBF => ("slash", "question"),
        0xC0 => ("grave", "asciitilde"), 0xDB => ("bracketleft", "braceleft"),
        0xDC => ("backslash", "bar"), 0xDD => ("bracketright", "braceright"),
        0xDE => ("apostrophe", "quotedbl"),
        _ => return None,
    })
}

/// 回傳 keysym 名稱；認不得回傳 None（交給應用程式）。
/// 字母：按著 Ctrl 一律小寫；否則 Shift 與 CapsLock 不同時為真才大寫。
pub fn keysym_name(vk: u32, shift: bool, ctrl: bool, caps: bool) -> Option<&'static str> {
    if let Some(s) = special(vk) {
        return Some(s);
    }
    if (0x41..=0x5A).contains(&vk) {
        let i = (vk - 0x41) as usize;
        if ctrl { return Some(LOWER[i]); }
        return Some(if shift != caps { UPPER[i] } else { LOWER[i] });
    }
    if (0x30..=0x39).contains(&vk) {
        let i = (vk - 0x30) as usize;
        return Some(if shift { SHIFTED_DIGITS[i] } else { DIGITS[i] });
    }
    if (VK_NUMPAD0..=VK_NUMPAD9).contains(&vk) {
        return Some(DIGITS[(vk - VK_NUMPAD0) as usize]);
    }
    oem(vk).map(|(plain, shifted)| if shift { shifted } else { plain })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn specials() {
        assert_eq!(keysym_name(VK_SPACE, false, false, false), Some("space"));
        assert_eq!(keysym_name(VK_BACK, false, false, false), Some("BackSpace"));
        assert_eq!(keysym_name(VK_RETURN, false, false, false), Some("Return"));
        assert_eq!(keysym_name(VK_ESCAPE, false, false, false), Some("Escape"));
        assert_eq!(keysym_name(VK_TAB, false, false, false), Some("Tab"));
        assert_eq!(keysym_name(VK_PRIOR, false, false, false), Some("Page_Up"));
        assert_eq!(keysym_name(VK_NEXT, false, false, false), Some("Page_Down"));
        assert_eq!(keysym_name(VK_DELETE, false, false, false), Some("Delete"));
        for (vk, n) in [(VK_LEFT, "Left"), (VK_UP, "Up"), (VK_RIGHT, "Right"), (VK_DOWN, "Down"),
                        (VK_HOME, "Home"), (VK_END, "End")] {
            assert_eq!(keysym_name(vk, false, false, false), Some(n));
        }
    }

    #[test]
    fn modifier_keys_ignore_flags() {
        for (vk, n) in [(VK_SHIFT, "Shift_L"), (VK_LSHIFT, "Shift_L"), (VK_RSHIFT, "Shift_R"),
                        (VK_CONTROL, "Control_L"), (VK_LCONTROL, "Control_L"), (VK_RCONTROL, "Control_R"),
                        (VK_MENU, "Alt_L"), (VK_LMENU, "Alt_L"), (VK_RMENU, "Alt_R"),
                        (VK_CAPITAL, "Caps_Lock")] {
            assert_eq!(keysym_name(vk, true, true, true), Some(n));
            assert_eq!(keysym_name(vk, false, false, false), Some(n));
        }
    }

    #[test]
    fn letters_shift_caps_ctrl() {
        let h = b'H' as u32;
        assert_eq!(keysym_name(h, false, false, false), Some("h"));
        assert_eq!(keysym_name(h, true, false, false), Some("H"));   // Shift → 大寫
        assert_eq!(keysym_name(h, false, false, true), Some("H"));   // CapsLock → 大寫
        assert_eq!(keysym_name(h, true, false, true), Some("h"));    // 兩者相消
        assert_eq!(keysym_name(h, true, true, false), Some("h"));    // Ctrl 一律小寫
        assert_eq!(keysym_name(h, false, true, true), Some("h"));
        assert_eq!(keysym_name(0x41, false, false, false), Some("a"));
        assert_eq!(keysym_name(0x5A, true, false, false), Some("Z"));
    }

    #[test]
    fn digits_and_numpad() {
        assert_eq!(keysym_name(0x31, false, false, false), Some("1"));
        assert_eq!(keysym_name(0x30, false, false, false), Some("0"));
        assert_eq!(keysym_name(0x31, true, false, false), Some("exclam"));
        assert_eq!(keysym_name(0x30, true, false, false), Some("parenright"));
        assert_eq!(keysym_name(0x39, true, false, false), Some("parenleft"));
        assert_eq!(keysym_name(0x32, true, false, false), Some("at"));
        assert_eq!(keysym_name(0x36, true, false, false), Some("asciicircum"));
        assert_eq!(keysym_name(VK_NUMPAD0, true, false, false), Some("0"));   // 數字鍵盤不受 Shift 影響
        assert_eq!(keysym_name(VK_NUMPAD9, false, false, false), Some("9"));
        assert_eq!(keysym_name(VK_NUMPAD9 + 1, false, false, false), None);   // VK_MULTIPLY 不認得
    }

    #[test]
    fn oem_punctuation_matches_pime_tests() {
        // tests/test_windows_pime.py：Ctrl＋, . / [ 與 Ctrl＋Shift＋/
        assert_eq!(keysym_name(0xBC, false, true, false), Some("comma"));
        assert_eq!(keysym_name(0xBE, false, true, false), Some("period"));
        assert_eq!(keysym_name(0xBF, true, true, false), Some("question"));
        assert_eq!(keysym_name(0xDB, false, true, false), Some("bracketleft"));
        let table = [
            (0xBA, "semicolon", "colon"), (0xBB, "equal", "plus"), (0xBC, "comma", "less"),
            (0xBD, "minus", "underscore"), (0xBE, "period", "greater"), (0xBF, "slash", "question"),
            (0xC0, "grave", "asciitilde"), (0xDB, "bracketleft", "braceleft"),
            (0xDC, "backslash", "bar"), (0xDD, "bracketright", "braceright"),
            (0xDE, "apostrophe", "quotedbl"),
        ];
        for (vk, plain, shifted) in table {
            assert_eq!(keysym_name(vk, false, false, false), Some(plain));
            assert_eq!(keysym_name(vk, true, false, false), Some(shifted));
        }
    }

    #[test]
    fn unknown_keys_pass_to_app() {
        for vk in [0x00, 0x70 /* F1 */, 0x5B /* LWin */, 0x5C, 0x90 /* NumLock */, 0xE5 /* IME process */] {
            assert_eq!(keysym_name(vk, false, false, false), None, "vk={vk:#x}");
        }
    }
}
