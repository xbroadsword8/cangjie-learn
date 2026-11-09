"""IBus 引擎外殼：把 IBus 按鍵事件轉給 Composer，再把結果畫到預編輯與候選窗。"""
import logging
import os
import time
from pathlib import Path

import gi

gi.require_version("IBus", "1.0")
from gi.repository import GLib, IBus  # noqa: E402

from .composer import RADICALS, Composer  # noqa: E402
from . import settings, sync  # noqa: E402
from .model import USER_DB, Model  # noqa: E402

LOG = logging.getLogger("cangjie-learn")
GRAY = 0x888888
RESET_GRACE = 0.5   # 送字後這麼短時間內的 reset 多半是應用程式自己觸發的，不斷開上文
# Chrome 會丟掉「帶 Ctrl 的按鍵事件處理期間（含前後一小段）」送出的文字，網址列、網頁、xterm.js 都一樣。
# 實測（tests/app_probe.py chrome）：放開後 20ms 送會被丟、60ms 以上收得到；固定時間差在忙碌桌面上不可靠。
# 另外 Ctrl 還按著時送字會被丟：xterm.js（PROBE_SEQ=hold 重現），以及使用者桌面上的一般 Chrome 網頁
# （2026-10-31 在真桌面實測；隔離 Xvfb 裡的 Chrome 文字框反而收得到，Xvfb 結果不能代表真桌面）。
# 做法：Ctrl＋標點的字先排隊，等 Ctrl 放開、且鍵盤安靜（沒有任何按下／放開）CTRL_COMMIT_DELAY_MS 後才送；
# 期間若有一般送字，排隊的字併在它前面一起送，順序不亂。
CTRL_COMMIT_DELAY_MS = int(os.environ.get("CJLEARN_CTRL_DELAY_MS", "30"))
# 存在這個檔就記錄每個按鍵事件（除錯用）
DEBUG_FLAG = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "cangjie-learn" / "debug"

SETTINGS_FILE = USER_DB.parent / "settings.json"
SETTINGS = settings.load(SETTINGS_FILE)   # 所有輸入框共用
PEERS = sync.PeerWatcher(USER_DB.parent)  # 其他電腦的學習資料（sync.py 同步到 sync/）
_model = None


def shared_model():
    global _model
    if _model is None:
        _model = Model()
    return _model


class CangjieLearnEngine(IBus.Engine):
    __gtype_name__ = "CangjieLearnEngine"

    def __init__(self, bus, object_path):
        super().__init__(connection=bus.get_connection(), object_path=object_path)
        self.comp = Composer(shared_model())
        self.table = IBus.LookupTable.new(9, 0, True, False)
        self.table.set_orientation(IBus.Orientation.VERTICAL)
        self._last_commit = 0.0
        self._queue = []     # 等鍵盤安靜才送的文字（Ctrl＋標點）
        self._timer = 0
        self._ctrl_down = False
        self.mode_prop = IBus.Property(
            key="InputMode", prop_type=IBus.PropType.NORMAL,
            label=IBus.Text.new_from_string("中"), symbol=IBus.Text.new_from_string("中"),
            tooltip=IBus.Text.new_from_string("單按 Shift 切換中／英"),
            sensitive=True, visible=True, state=IBus.PropState.UNCHECKED,
        )
        self.clear_prop = IBus.Property(
            key="ClearOnError", prop_type=IBus.PropType.TOGGLE,
            label=IBus.Text.new_from_string("打錯碼按空白清掉"),
            tooltip=IBus.Text.new_from_string("沒有候選字時按空白或數字鍵，清掉字碼"),
            sensitive=True, visible=True, state=IBus.PropState.UNCHECKED,
        )
        self.punct_prop = IBus.Property(
            key="FullPunct", prop_type=IBus.PropType.TOGGLE,
            label=IBus.Text.new_from_string("標點直接出全形"),
            tooltip=IBus.Text.new_from_string("中文模式按 ，。？！ 等不用加 Ctrl（仿微軟倉頡）"),
            sensitive=True, visible=True, state=IBus.PropState.UNCHECKED,
        )
        self.sync_prop = IBus.Property(   # 同步狀態（只顯示，沒設定同步就隱藏）
            key="SyncStatus", prop_type=IBus.PropType.NORMAL, label=IBus.Text.new_from_string(""),
            sensitive=False, visible=False, state=IBus.PropState.UNCHECKED,
        )
        self.props_list = IBus.PropList()
        self.props_list.append(self.mode_prop)
        self.props_list.append(self.clear_prop)
        self.props_list.append(self.punct_prop)
        self.props_list.append(self.sync_prop)
        self._apply_settings()

    # --- 按鍵 ---
    def do_process_key_event(self, keyval, keycode, state):
        try:
            if state & (IBus.ModifierType.SUPER_MASK | IBus.ModifierType.MOD4_MASK):
                return False
            name = IBus.keyval_name(keyval) or ""
            release = bool(state & IBus.ModifierType.RELEASE_MASK)
            if name in ("Control_L", "Control_R"):
                self._ctrl_down = not release
            if self._queue:
                self._arm_timer()   # 還有按鍵活動：重新計時
            if DEBUG_FLAG.exists():
                LOG.info("key %s keyval=%#x keycode=%s state=%#x", name, keyval, keycode, state)
            was_chinese = self.comp.chinese
            ctrl = bool(state & IBus.ModifierType.CONTROL_MASK)
            r = self.comp.process(
                name,
                ctrl=ctrl,
                shift=bool(state & IBus.ModifierType.SHIFT_MASK),
                alt=bool(state & IBus.ModifierType.MOD1_MASK),
                release=release,
            )
            if r.commit and ctrl and not release:
                self._queue.append(r.commit)
                self._arm_timer()
            elif r.commit:
                self._commit(r.commit)
            self._render()
            if self.comp.chinese != was_chinese:
                self._update_mode()
            return r.handled
        except Exception:
            LOG.exception("process_key_event 失敗（key=%s state=%s）", keyval, state)
            return False

    def _arm_timer(self):
        if self._timer:
            GLib.source_remove(self._timer)
            self._timer = 0
        if not self._ctrl_down:   # Ctrl 放開時（那個放開事件也會走到這裡）才開始計時
            self._timer = GLib.timeout_add(CTRL_COMMIT_DELAY_MS, self._flush_queue)

    def _cancel_queue(self):
        if self._timer:
            GLib.source_remove(self._timer)
            self._timer = 0
        self._queue.clear()

    def _flush_queue(self):
        self._timer = 0
        if self._queue:
            text = "".join(self._queue)
            self._queue.clear()
            self._commit(text)
        return False  # 只跑一次

    def _commit(self, text):
        if self._queue:   # 排隊中的 Ctrl＋標點放在前面，順序不亂
            text = "".join(self._queue) + text
            self._cancel_queue()
        # 先清掉預編輯再送字：GTK4 程式（如檔案總管）在預編輯還顯示時收到送字，會把部件也一起插入
        self.update_preedit_text(IBus.Text.new_from_string(""), 0, False)
        self.commit_text(IBus.Text.new_from_string(text))
        self._last_commit = time.monotonic()

    # --- 畫面 ---
    def _render(self):
        if not self.comp.code:
            self.hide_preedit_text()
            self.hide_lookup_table()
            self.hide_auxiliary_text()
            return
        pre = self.comp.preedit()
        text = IBus.Text.new_from_string(pre)
        text.append_attribute(IBus.AttrType.UNDERLINE, IBus.AttrUnderline.SINGLE, 0, len(pre))
        self.update_preedit_text(text, len(pre), True)

        self.table.clear()
        page = self.comp.page_cands()
        for c in page:
            if c.exact:
                t = IBus.Text.new_from_string(c.ch)
            else:  # 補完候選：灰字附上還沒打的部件，順便練碼
                rest = "".join(RADICALS[k] for k in c.code[len(self.comp.code):])
                t = IBus.Text.new_from_string(f"{c.ch} {rest}")
                t.append_attribute(IBus.AttrType.FOREGROUND, GRAY, 1, 2 + len(rest))
            self.table.append_candidate(t)
        if page:
            self.table.set_cursor_pos(self.comp.cursor)
            self.update_lookup_table(self.table, True)
            pages = (len(self.comp.cands) + 8) // 9
            if pages > 1:
                self.update_auxiliary_text(
                    IBus.Text.new_from_string(f"{self.comp.page + 1}/{pages}"), True)
            else:
                self.hide_auxiliary_text()
        else:
            self.hide_lookup_table()
            self.hide_auxiliary_text()

    def _update_mode(self):
        s = "中" if self.comp.chinese else "英"
        self.mode_prop.set_label(IBus.Text.new_from_string(s))
        self.mode_prop.set_symbol(IBus.Text.new_from_string(s))
        self.update_property(self.mode_prop)

    def _apply_settings(self):
        on = SETTINGS["clear_on_error"]
        self.comp.clear_on_error = on
        self.clear_prop.set_state(IBus.PropState.CHECKED if on else IBus.PropState.UNCHECKED)
        full = SETTINGS["full_punct"]
        self.comp.full_punct = full
        self.punct_prop.set_state(IBus.PropState.CHECKED if full else IBus.PropState.UNCHECKED)
        text = sync.status_text(USER_DB.parent)
        self.sync_prop.set_label(IBus.Text.new_from_string(text))
        self.sync_prop.set_visible(bool(text))

    def do_property_activate(self, prop_name, state):
        if prop_name == "ClearOnError":
            SETTINGS["clear_on_error"] = state == IBus.PropState.CHECKED
            try:
                settings.update(SETTINGS_FILE, clear_on_error=SETTINGS["clear_on_error"])
            except OSError:
                LOG.exception("儲存設定失敗")
            self._apply_settings()
            self.update_property(self.clear_prop)
        elif prop_name == "FullPunct":
            SETTINGS["full_punct"] = state == IBus.PropState.CHECKED
            try:
                settings.update(SETTINGS_FILE, full_punct=SETTINGS["full_punct"])
            except OSError:
                LOG.exception("儲存設定失敗")
            self._apply_settings()
            self.update_property(self.punct_prop)

    # --- 滑鼠與系統事件 ---
    def do_candidate_clicked(self, index, button, state):
        ch = self.comp._pick(index)
        if ch:
            self._commit(ch)
        self._render()

    def do_page_down(self):
        self.comp.process("Page_Down")
        self._render()
        return True

    def do_page_up(self):
        self.comp.process("Page_Up")
        self._render()
        return True

    def do_focus_in(self):
        self._ctrl_down = False
        PEERS.poll(shared_model())
        self._apply_settings()
        self.register_properties(self.props_list)
        self._update_mode()
        self.comp.reset()
        self._render()

    def do_focus_out(self):
        self._cancel_queue()   # 焦點已離開，不要送到別的視窗
        self.comp.reset()
        self._render()

    def do_reset(self):
        keep_ctx = time.monotonic() - self._last_commit < RESET_GRACE and not self.comp.code
        ctx = self.comp.ctx
        self.comp.reset()
        if keep_ctx:
            self.comp.ctx = ctx
        self._render()

    def do_disable(self):
        self.comp.reset()
        self._render()


class Factory(IBus.Factory):
    def __init__(self, bus):
        self.bus = bus
        self.n = 0
        super().__init__(connection=bus.get_connection(), object_path=IBus.PATH_FACTORY)

    def do_create_engine(self, engine_name):
        self.n += 1
        return CangjieLearnEngine(self.bus, f"/org/freedesktop/IBus/CangjieLearn/Engine/{self.n}")
