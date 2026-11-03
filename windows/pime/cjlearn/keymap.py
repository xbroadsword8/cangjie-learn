"""Windows 虛擬鍵碼（VK）→ X keysym 名稱，讓 Linux 版的 Composer 原封不動沿用。不依賴 PIME，可在 Linux 測。"""

VK_BACK, VK_TAB, VK_RETURN = 0x08, 0x09, 0x0D
VK_SHIFT, VK_CONTROL, VK_MENU, VK_CAPITAL, VK_ESCAPE = 0x10, 0x11, 0x12, 0x14, 0x1B
VK_SPACE, VK_PRIOR, VK_NEXT, VK_END, VK_HOME = 0x20, 0x21, 0x22, 0x23, 0x24
VK_LEFT, VK_UP, VK_RIGHT, VK_DOWN, VK_DELETE = 0x25, 0x26, 0x27, 0x28, 0x2E
VK_LWIN, VK_RWIN = 0x5B, 0x5C
VK_NUMPAD0, VK_NUMPAD9 = 0x60, 0x69
VK_LSHIFT, VK_RSHIFT, VK_LCONTROL, VK_RCONTROL, VK_LMENU, VK_RMENU = 0xA0, 0xA1, 0xA2, 0xA3, 0xA4, 0xA5

SPECIAL = {
    VK_BACK: "BackSpace", VK_TAB: "Tab", VK_RETURN: "Return", VK_ESCAPE: "Escape", VK_SPACE: "space",
    VK_PRIOR: "Page_Up", VK_NEXT: "Page_Down", VK_END: "End", VK_HOME: "Home",
    VK_LEFT: "Left", VK_UP: "Up", VK_RIGHT: "Right", VK_DOWN: "Down", VK_DELETE: "Delete",
    VK_SHIFT: "Shift_L", VK_LSHIFT: "Shift_L", VK_RSHIFT: "Shift_R",
    VK_CONTROL: "Control_L", VK_LCONTROL: "Control_L", VK_RCONTROL: "Control_R",
    VK_MENU: "Alt_L", VK_LMENU: "Alt_L", VK_RMENU: "Alt_R", VK_CAPITAL: "Caps_Lock",
}
# 美式鍵盤標點鍵：(不按 Shift, 按 Shift)
OEM = {
    0xBA: ("semicolon", "colon"), 0xBB: ("equal", "plus"), 0xBC: ("comma", "less"),
    0xBD: ("minus", "underscore"), 0xBE: ("period", "greater"), 0xBF: ("slash", "question"),
    0xC0: ("grave", "asciitilde"), 0xDB: ("bracketleft", "braceleft"), 0xDC: ("backslash", "bar"),
    0xDD: ("bracketright", "braceright"), 0xDE: ("apostrophe", "quotedbl"),
}
SHIFTED_DIGITS = ["parenright", "exclam", "at", "numbersign", "dollar", "percent",
                  "asciicircum", "ampersand", "asterisk", "parenleft"]


def keysym_name(vk, shift=False, ctrl=False, caps=False):
    """回傳 keysym 名稱；認不得回傳空字串（交給應用程式）。"""
    if vk in SPECIAL:
        return SPECIAL[vk]
    if 0x41 <= vk <= 0x5A:                       # A–Z
        ch = chr(vk)
        if ctrl:
            return ch.lower()
        return ch if (shift != caps) else ch.lower()
    if 0x30 <= vk <= 0x39:                       # 數字列
        return SHIFTED_DIGITS[vk - 0x30] if shift else chr(vk)
    if VK_NUMPAD0 <= vk <= VK_NUMPAD9:
        return chr(0x30 + vk - VK_NUMPAD0)
    if vk in OEM:
        return OEM[vk][1 if shift else 0]
    return ""
