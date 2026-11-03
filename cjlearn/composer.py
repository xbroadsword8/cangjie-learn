"""按鍵狀態機：倉頡組字、選字、標點、中英切換。不依賴 IBus，鍵用 X keysym 名稱表示。

標點邏輯（仿酷倉）：中文模式下標點鍵預設出半形英文標點；加按 Ctrl 才出中文全形標點。
中英切換：單按一下 Shift（中間沒按別的鍵）。
"""

RADICALS = dict(zip("abcdefghijklmnopqrstuvwxyz", "日月金木水火土竹戈十大中一弓人心手口尸廿山女田難卜重"))

# Ctrl＋標點 → 中文標點（keysym 名稱；Shift 組合的 keysym 已是上檔符號）
CJK_PUNCT = {
    "comma": "，", "period": "。", "semicolon": "；", "colon": "：",
    "question": "？", "exclam": "！", "apostrophe": "、", "backslash": "、",
    "bracketleft": "「", "bracketright": "」", "braceleft": "『", "braceright": "』",
    "parenleft": "（", "parenright": "）", "less": "《", "greater": "》",
    "quotedbl": "＂", "slash": "／", "asciitilde": "～", "asciicircum": "……",
    "underscore": "——", "minus": "－", "at": "＠", "numbersign": "＃",
    "dollar": "＄", "percent": "％", "ampersand": "＆", "asterisk": "＊",
    "plus": "＋", "equal": "＝", "bar": "｜", "grave": "‵",
}
ASCII_PUNCT = {
    "comma": ",", "period": ".", "semicolon": ";", "colon": ":", "question": "?",
    "exclam": "!", "apostrophe": "'", "quotedbl": '"', "backslash": "\\", "slash": "/",
    "bracketleft": "[", "bracketright": "]", "braceleft": "{", "braceright": "}",
    "parenleft": "(", "parenright": ")", "less": "<", "greater": ">", "asciitilde": "~",
    "asciicircum": "^", "underscore": "_", "minus": "-", "at": "@", "numbersign": "#",
    "dollar": "$", "percent": "%", "ampersand": "&", "asterisk": "*", "plus": "+",
    "equal": "=", "bar": "|", "grave": "`",
}
CONTEXT_BREAK = {"Return", "KP_Enter", "Tab", "Left", "Right", "Up", "Down", "Home", "End",
                 "Page_Up", "Page_Down", "Delete", "Escape"}
MAX_CODE = 5
PAGE = 9


class Result:
    """handled：是否吃掉此鍵；commit：要送出的文字。"""
    __slots__ = ("handled", "commit")

    def __init__(self, handled, commit=""):
        self.handled, self.commit = handled, commit


class Composer:
    def __init__(self, model):
        self.model = model
        self.chinese = True
        self.code = ""
        self.cands = []
        self.page = 0
        self.cursor = 0          # 頁內游標
        self.ctx = ""            # 最近送出的中文字（上文）
        self.clear_on_error = True   # 打錯碼（沒有候選）按空白或數字鍵：清掉字碼
        self._shift_alone = False

    # --- 對外狀態 ---
    def preedit(self):
        return "".join(RADICALS[c] for c in self.code)

    def page_cands(self):
        return self.cands[self.page * PAGE:(self.page + 1) * PAGE]

    def reset(self):
        """焦點改變、游標移動：清組字並斷開上文。"""
        self.code, self.cands, self.page, self.cursor = "", [], 0, 0
        self.ctx = ""

    # --- 內部 ---
    def _refresh(self):
        self.cands = self.model.candidates(self.code, self.ctx)
        self.page = self.cursor = 0

    def _clear(self):
        self.code, self.cands, self.page, self.cursor = "", [], 0, 0

    def _pick(self, idx_in_page=None):
        """送出目前頁的第 idx 個候選（預設游標所在），回傳字；沒有候選回傳空字串。"""
        page = self.page_cands()
        i = self.cursor if idx_in_page is None else idx_in_page
        if i >= len(page):
            return ""
        ch = page[i].ch
        self.model.learn(ch, self.ctx, corrected=(self.page * PAGE + i) > 0)
        self.ctx = (self.ctx + ch)[-3:]
        self._clear()
        return ch

    def _flush(self):
        """有未完成的碼時，送出第一候選（沒有候選就丟棄碼）。"""
        if not self.code:
            return ""
        if not self.cands:
            self._clear()
            return ""
        return self._pick(0)

    # --- 主入口 ---
    def process(self, key, ctrl=False, shift=False, alt=False, release=False):
        # 單按 Shift 切換中英
        if key in ("Shift_L", "Shift_R"):
            if not release:
                self._shift_alone = not (ctrl or alt)
                return Result(False)
            if self._shift_alone:
                self._shift_alone = False
                commit = self.code if self.code else ""   # 打一半切英文：保留已打的字母
                self._clear()
                self.chinese = not self.chinese
                self.ctx = ""
                return Result(bool(commit), commit)
            return Result(False)
        if release:
            return Result(False)
        self._shift_alone = False

        # Ctrl＋標點 → 中文標點（中英模式皆可用）
        if ctrl and not alt and key in CJK_PUNCT:
            out = self._flush() + CJK_PUNCT[key]
            self.ctx = ""
            return Result(True, out)

        if not self.chinese:
            if key in CONTEXT_BREAK:
                self.ctx = ""
            return Result(False)

        if ctrl or alt:
            return Result(False)

        # 組字
        if len(key) == 1 and "a" <= key <= "z":
            if len(self.code) >= MAX_CODE:
                return Result(True)
            self.code += key
            self._refresh()
            return Result(True)

        if self.code:
            return self._process_composing(key)

        # 沒有組字中
        if key == "BackSpace":
            self.ctx = self.ctx[:-1]
        elif key in CONTEXT_BREAK or key == "space" or key in ASCII_PUNCT:
            self.ctx = ""
        elif len(key) == 1 and "A" <= key <= "Z":
            self.ctx = ""
        return Result(False)

    def _process_composing(self, key):
        page = self.page_cands()
        if not self.cands and self.clear_on_error and (key == "space" or len(key) == 1 and "1" <= key <= "9"):
            self._clear()
            return Result(True)
        if key == "space":
            return Result(True, self._pick())
        if len(key) == 1 and "1" <= key <= "9":
            i = int(key) - 1
            if i < len(page):
                return Result(True, self._pick(i))
            return Result(True)
        if key == "BackSpace":
            self.code = self.code[:-1]
            if self.code:
                self._refresh()
            else:
                self._clear()
            return Result(True)
        if key == "Escape":
            self._clear()
            return Result(True)
        if key in ("Return", "KP_Enter"):
            raw = self.code
            self._clear()
            self.ctx = ""
            return Result(True, raw)
        if key in ("Page_Down", "equal", "KP_Page_Down"):
            if (self.page + 1) * PAGE < len(self.cands):
                self.page += 1
                self.cursor = 0
            return Result(True)
        if key in ("Page_Up", "minus", "KP_Page_Up"):
            if self.page > 0:
                self.page -= 1
                self.cursor = 0
            return Result(True)
        if key in ("Down", "Right"):
            if self.cursor + 1 < len(page):
                self.cursor += 1
            elif (self.page + 1) * PAGE < len(self.cands):
                self.page += 1
                self.cursor = 0
            return Result(True)
        if key in ("Up", "Left"):
            if self.cursor > 0:
                self.cursor -= 1
            elif self.page > 0:
                self.page -= 1
                self.cursor = PAGE - 1
            return Result(True)
        if key in ASCII_PUNCT:
            out = self._flush() + ASCII_PUNCT[key]
            self.ctx = ""
            return Result(True, out)
        if len(key) == 1 and "A" <= key <= "Z":
            out = self._flush() + key
            self.ctx = ""
            return Result(True, out)
        # 其他鍵（數字 0、Tab…）：先送出第一候選，鍵本身交給應用程式
        out = self._flush()
        self.ctx = ""
        return Result(False, out)
