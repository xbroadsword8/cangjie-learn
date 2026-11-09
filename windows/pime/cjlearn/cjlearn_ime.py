#! python3
"""倉頡學習版：PIME（Windows TSF）外殼。選字與按鍵邏輯沿用 Linux 版的 core/（model.py、composer.py）。

PIME 流程：filterKeyDown 問要不要這個鍵 → 要的話再呼叫 onKeyDown 處理。
Composer.process 會改狀態，所以在 filterKeyDown 就處理並暫存結果，onKeyDown 只負責輸出。

⚠ filterKeyDown／filterKeyUp（以及 onCommand 等沒有 edit session 的呼叫）絕不能送 showMessage：
PIME 1.3 的 PIMEClient.cpp:133 在沒有 session 時照樣 session->context()，空指標讓宿主程式當掉
（2026-11-01 在 Win11 測試機 讓 explorer.exe 當掉）。畫面相關的回覆一律留到 onKeyDown／onKeyUp。
"""
import os
import time

from keycodes import VK_CAPITAL, VK_CONTROL, VK_LWIN, VK_MENU, VK_RWIN, VK_SHIFT
from textService import TextService

from .core import settings, sync
from .core.composer import RADICALS, Composer
from .core.model import Model
from .keymap import keysym_name

HERE = os.path.dirname(os.path.abspath(__file__))
# 自帶圖示：PIME 預設安裝不含 cinbase（倉頡等模組），不能借用它的 icons（2026-11-07 新電腦裝不起來）
ICON_DIR = os.path.join(HERE, "icons")
USER_DB = os.path.join(os.environ.get("APPDATA", HERE), "PIME", "cjlearn", "user.db")
SETTINGS_FILE = os.path.join(os.path.dirname(USER_DB), "settings.json")
SETTINGS = settings.load(SETTINGS_FILE)   # 所有輸入框共用
PEERS = sync.PeerWatcher(os.path.dirname(USER_DB))  # 其他電腦的學習資料（sync.py 同步到 sync\）
ID_MODE_ICON = 1
ID_CLEAR_ON_ERROR = 2
ID_SYNC_STATUS = 3
ID_FULL_PUNCT = 4
DUP_FILTER_SEC = 0.05   # TSF 偶爾對同一個按鍵重複呼叫 filterKeyDown，這段時間內的重複不再處理

_model = None


def shared_model():
    global _model
    if _model is None:
        os.makedirs(os.path.dirname(USER_DB), exist_ok=True)
        _model = Model(user_db=USER_DB)
    return _model


class CangjieLearnTextService(TextService):
    def __init__(self, client):
        TextService.__init__(self, client)
        self.comp = Composer(shared_model())
        self._pending = None        # (keyCode, Result) filterKeyDown 算好、等 onKeyDown 輸出
        self._pending_up = None
        self._mode_changed = False  # filter 階段切了中英，等 onKeyDown／onKeyUp 再更新圖示與提示
        self._last_filter = (None, 0.0)

    # --- 啟用／停用 ---
    def onActivate(self):
        TextService.onActivate(self)
        self.comp.clear_on_error = SETTINGS["clear_on_error"]
        self.comp.full_punct = SETTINGS["full_punct"]
        PEERS.poll(shared_model())
        self.setSelKeys("123456789")
        self.customizeUI(candPerRow=1, candUseCursor=True)
        self.addButton("windows-mode-icon", icon=self._mode_icon(), tooltip="中英文切換（單按 Shift）",
                       commandId=ID_MODE_ICON)
        self.setKeyboardOpen(True)
        self.comp.reset()

    def onDeactivate(self):
        TextService.onDeactivate(self)
        self.removeButton("windows-mode-icon")
        self.comp.reset()

    def onKeyboardStatusChanged(self, opened):
        TextService.onKeyboardStatusChanged(self, opened)
        self.keyboardOpen = opened
        self.comp.reset()
        self._render()

    def onCompositionTerminated(self, forced):
        TextService.onCompositionTerminated(self, forced)
        if forced:   # 切換視窗等被迫結束：丟掉組字並斷開上文
            self.comp.reset()
            self._render()

    def onMenu(self, buttonId):
        # 工作列「中／英」圖示按右鍵的選單（沒有 edit session：只回選單，不送畫面）
        if buttonId == "windows-mode-icon":
            items = [{"text": "打錯碼按空白清掉", "id": ID_CLEAR_ON_ERROR, "checked": SETTINGS["clear_on_error"]},
                     {"text": "標點直接出全形（，。？！）", "id": ID_FULL_PUNCT, "checked": SETTINGS["full_punct"]}]
            status = sync.status_text(os.path.dirname(USER_DB))
            if status:
                items.append({"text": status, "id": ID_SYNC_STATUS, "enabled": False})
            return items
        return None

    def onCommand(self, commandId, commandType):
        if commandId == ID_CLEAR_ON_ERROR:
            SETTINGS["clear_on_error"] = not SETTINGS["clear_on_error"]
            self.comp.clear_on_error = SETTINGS["clear_on_error"]
            try:
                settings.update(SETTINGS_FILE, clear_on_error=SETTINGS["clear_on_error"])
            except OSError:
                pass
        elif commandId == ID_FULL_PUNCT:
            SETTINGS["full_punct"] = not SETTINGS["full_punct"]
            self.comp.full_punct = SETTINGS["full_punct"]
            try:
                settings.update(SETTINGS_FILE, full_punct=SETTINGS["full_punct"])
            except OSError:
                pass
        elif commandId == ID_MODE_ICON:
            self.comp.chinese = not self.comp.chinese
            self.comp.reset()
            self._render()
            self._update_mode(message=False)    # onCommand 沒有 edit session，不能 showMessage

    # --- 按鍵 ---
    def _process(self, keyEvent, release):
        if not self.keyboardOpen:
            return None
        if keyEvent.isKeyDown(VK_LWIN) or keyEvent.isKeyDown(VK_RWIN):
            return None
        shift = keyEvent.isKeyDown(VK_SHIFT)
        ctrl = keyEvent.isKeyDown(VK_CONTROL)
        name = keysym_name(keyEvent.keyCode, shift=shift, ctrl=ctrl, caps=keyEvent.isKeyToggled(VK_CAPITAL))
        if not name:
            return None
        return self.comp.process(name, ctrl=ctrl, shift=shift, alt=keyEvent.isKeyDown(VK_MENU), release=release)

    def filterKeyDown(self, keyEvent):
        now = time.monotonic()
        last_code, last_t = self._last_filter
        if self._pending and last_code == keyEvent.keyCode and now - last_t < DUP_FILTER_SEC:
            return True
        self._last_filter = (keyEvent.keyCode, now)
        was_chinese = self.comp.chinese
        r = self._process(keyEvent, release=False)
        if r is None:
            return False
        if self.comp.chinese != was_chinese:
            self._mode_changed = True
        # TSF 只能在 onKeyDown 裡送字，所以「沒吃掉但要先送出第一候選」的鍵也一併吃掉
        if r.handled or r.commit:
            self._pending = (keyEvent.keyCode, r)
            return True
        return False

    def onKeyDown(self, keyEvent):
        if self._pending and self._pending[0] == keyEvent.keyCode:
            r = self._pending[1]
        else:   # 沒經過 filterKeyDown 就直接來（少數程式）：現在處理
            r = self._process(keyEvent, release=False)
            if r is None or not (r.handled or r.commit):
                self._pending = None
                return False
        self._pending = None
        if r.commit:
            self.setCommitString(r.commit)
        self._render()
        self._flush_mode()
        return True

    def filterKeyUp(self, keyEvent):
        was_chinese = self.comp.chinese
        r = self._process(keyEvent, release=True)
        if r is None:
            return False
        if self.comp.chinese != was_chinese:
            self._mode_changed = True
            self._pending_up = r
            return True     # 要在 onKeyUp 刷新畫面、換圖示（並送出切換前打到一半的字母）
        return False

    def onKeyUp(self, keyEvent):
        r, self._pending_up = self._pending_up, None
        if r and r.commit:
            self.setCommitString(r.commit)
        self._render()
        self._flush_mode()
        return True

    # --- 畫面 ---
    def _render(self):
        c = self.comp
        if not c.code:
            self.setCompositionString("")
            self.setShowCandidates(False)
            self.setCandidateList([])
            return
        pre = c.preedit()
        self.setCompositionString(pre)
        self.setCompositionCursor(len(pre))
        page = c.page_cands()
        # 補完候選附上還沒打的部件，順便練碼
        self.setCandidateList([p.ch if p.exact else p.ch + " " + "".join(RADICALS[k] for k in p.code[len(c.code):])
                               for p in page])
        if page:
            self.setCandidateCursor(c.cursor)
            self.setShowCandidates(True)
        else:
            self.setShowCandidates(False)

    def _mode_icon(self):
        name = "chi_half_capsoff.ico" if self.comp.chinese else "eng_half_capsoff.ico"
        return os.path.abspath(os.path.join(ICON_DIR, name))

    def _flush_mode(self):
        if self._mode_changed:
            self._mode_changed = False
            self._update_mode(message=True)

    def _update_mode(self, message):
        self.changeButton("windows-mode-icon", icon=self._mode_icon())
        if message and not self.client.isUiLess:
            self.showMessage("中" if self.comp.chinese else "英", 1)
