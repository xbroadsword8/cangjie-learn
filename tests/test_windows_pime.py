"""用 PIME 1.3 真正的 textService.py 模擬 Windows 按鍵訊息，測 windows/pime/cjlearn 外殼（不需 Windows）。"""
import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
VK = dict(SHIFT=0x10, CONTROL=0x11, MENU=0x12, SPACE=0x20, BACK=0x08, RETURN=0x0D, ESCAPE=0x1B,
          COMMA=0xBC, PERIOD=0xBE, OEM2=0xBF, OEM4=0xDB, TAB=0x09)


@pytest.fixture
def svc(tmp_path, monkeypatch):
    build = Path(subprocess.check_output([str(ROOT / "windows" / "build.sh")], text=True).strip())
    pkg = tmp_path / "input_methods"
    shutil.copytree(build, pkg / "cjlearn")
    (pkg / "__init__.py").touch()
    monkeypatch.setenv("APPDATA", str(tmp_path / "appdata"))   # 學習資料寫到暫存目錄
    monkeypatch.syspath_prepend(str(ROOT / "tests" / "fixtures" / "pime13"))
    monkeypatch.syspath_prepend(str(tmp_path))
    for m in [m for m in sys.modules if m.startswith("input_methods")]:
        del sys.modules[m]
    from input_methods.cjlearn import cjlearn_ime

    class Client:
        isWindows8Above = True
        isUiLess = False

    s = cjlearn_ime.CangjieLearnTextService(Client())
    s.handleRequest({"method": "onActivate", "isKeyboardOpen": True})
    yield s
    assert not (ROOT / "windows" / "build" / "cjlearn" / "data" / "user.db").exists()


# PIME 1.3 的 DLL 只在 onKeyDown／onKeyUp 傳 edit session（PIMEClient.cpp handleRpcResponse 預設 session=nullptr）。
# 沒有 session 時：showMessage 會對空指標取值、讓宿主程式當掉；commitString／compositionString 會被丟掉。
HAS_SESSION = {"onKeyDown", "onKeyUp"}


def check_reply(method, reply):
    if method not in HAS_SESSION:
        bad = {"showMessage", "commitString"} & reply.keys()
        assert not bad, f"{method} 的回覆含 {bad}：沒有 edit session，會當掉或掉字"


class Keyboard:
    def __init__(self, svc):
        self.svc, self.down, self.out = svc, set(), ""

    def _msg(self, method, vk):
        states = [0] * 256
        for k in self.down:
            states[k] = 0x80
        ch = vk if 0x41 <= vk <= 0x5A else 0
        return {"method": method, "charCode": ch, "keyCode": vk, "repeatCount": 1,
                "scanCode": 0, "isExtended": False, "keyStates": states}

    def _req(self, method, vk):
        r = self.svc.handleRequest(self._msg(method, vk))
        check_reply(method, r)
        self.out += r.get("commitString", "")
        return r

    def press(self, vk):
        self.down.add(vk)
        if self._req("filterKeyDown", vk).get("return"):
            self._req("onKeyDown", vk)
            return True
        return False

    def release(self, vk):
        if self._req("filterKeyUp", vk).get("return"):
            self._req("onKeyUp", vk)
        self.down.discard(vk)

    def tap(self, vk, *mods):
        for m in mods:
            self.press(m)
        handled = self.press(vk)
        self.release(vk)
        for m in reversed(mods):
            self.release(m)
        return handled

    def type(self, s):
        for ch in s:
            self.tap({" ": VK["SPACE"], ",": VK["COMMA"]}.get(ch, ord(ch.upper())))
        return self


def test_basic_and_context(svc):
    kb = Keyboard(svc).type("hqi oiar tcp grtr ")
    assert kb.out == "我倉恭喜"


def test_candidates_shown(svc):
    kb = Keyboard(svc)
    kb.type("grt")
    assert svc.compositionString == "土口廿"
    assert svc.showCandidates and svc.candidateList


def test_ascii_and_ctrl_punct(svc):
    kb = Keyboard(svc)
    kb.type("hqi,")
    assert kb.out == "我,"
    kb.out = ""
    assert kb.tap(VK["COMMA"], VK["CONTROL"])
    kb.tap(VK["PERIOD"], VK["CONTROL"])
    kb.tap(VK["OEM2"], VK["CONTROL"], VK["SHIFT"])
    kb.tap(VK["OEM4"], VK["CONTROL"])
    assert kb.out == "，。？「"


def test_plain_punct_passes_through(svc):
    kb = Keyboard(svc)
    assert kb.tap(VK["PERIOD"]) is False
    assert kb.tap(ord("C"), VK["CONTROL"]) is False


def test_full_punct_menu(svc, tmp_path):
    kb = Keyboard(svc)
    menu = svc.handleRequest({"method": "onMenu", "id": "windows-mode-icon"})
    check_reply("onMenu", menu)
    item = [x for x in menu["return"] if "全形" in x.get("text", "")][0]
    assert item["checked"] is False
    check_reply("onCommand", svc.handleRequest({"method": "onCommand", "id": item["id"], "type": 1}))
    cfg = tmp_path / "appdata" / "PIME" / "cjlearn" / "settings.json"
    assert '"full_punct": true' in cfg.read_text()
    kb.type("hqi,")
    assert kb.out == "我，"
    kb.out = ""
    assert kb.tap(VK["PERIOD"]) is True
    assert kb.out == "。"


def test_shift_toggle(svc):
    kb = Keyboard(svc)
    kb.tap(VK["SHIFT"])
    assert svc.comp.chinese is False
    assert kb.tap(ord("A")) is False
    kb.tap(VK["SHIFT"])
    kb.type("a ")
    assert kb.out == "日"


def test_shift_letter_does_not_toggle(svc):
    kb = Keyboard(svc)
    kb.tap(ord("A"), VK["SHIFT"])
    assert svc.comp.chinese is True


def test_composing_swallows_other_keys_and_commits(svc):
    kb = Keyboard(svc)
    kb.type("hqi")
    assert kb.tap(VK["TAB"]) is True      # 組字中的 Tab：送出第一候選（Windows 版吃掉 Tab）
    assert kb.out == "我"


def test_duplicate_filter_not_processed_twice(svc):
    kb = Keyboard(svc)
    kb.down.add(ord("H"))
    kb._req("filterKeyDown", ord("H"))
    kb._req("filterKeyDown", ord("H"))   # TSF 重複詢問
    kb._req("onKeyDown", ord("H"))
    assert svc.comp.code == "h"


def test_learning_db_location(svc, tmp_path):
    Keyboard(svc).type("hqi ")
    assert (tmp_path / "appdata" / "PIME" / "cjlearn" / "user.db").exists()


def test_no_session_replies_are_safe(svc):
    """切中英（filterKeyUp 判定）與點圖示（onCommand）都沒有 edit session，不能帶 showMessage。"""
    kb = Keyboard(svc)
    kb.tap(VK["SHIFT"])                              # 切英文：提示要在 onKeyUp 才送
    assert not kb.tap(ord("A"))                      # 英文模式：字母直接交給程式
    kb.tap(VK["SHIFT"])                              # 切回中文
    for _ in range(2):                               # 點圖示兩次：切英文再切回中文
        check_reply("onCommand", svc.handleRequest({"method": "onCommand", "id": 1, "type": 0}))
    check_reply("onKeyboardStatusChanged", svc.handleRequest({"method": "onKeyboardStatusChanged", "opened": True}))
    check_reply("onCompositionTerminated", svc.handleRequest({"method": "onCompositionTerminated", "forced": True}))
    kb.type("hqi ")
    assert kb.out == "我"


def test_clear_on_error_menu(svc, tmp_path):
    kb = Keyboard(svc)
    kb.type("qqqq hqi ")
    assert kb.out == "我"                                      # 預設：打錯碼按空白清掉
    menu = svc.handleRequest({"method": "onMenu", "id": "windows-mode-icon"})
    check_reply("onMenu", menu)
    item = menu["return"][0]
    assert item["checked"] is True
    r = svc.handleRequest({"method": "onCommand", "id": item["id"], "type": 1})
    check_reply("onCommand", r)
    cfg = tmp_path / "appdata" / "PIME" / "cjlearn" / "settings.json"
    assert '"clear_on_error": false' in cfg.read_text()
    assert svc.comp.chinese is True                            # 選單項目不是切中英
    kb.out = ""
    kb.type("qqqq ")
    assert svc.comp.code == "qqqq" and kb.out == ""             # 關掉後停在那裡
    menu = svc.handleRequest({"method": "onMenu", "id": "windows-mode-icon"})
    assert menu["return"][0]["checked"] is False


def test_peers_and_sync_status(svc, tmp_path):
    import json
    from input_methods.cjlearn import cjlearn_ime
    data = tmp_path / "appdata" / "PIME" / "cjlearn"
    (data / "sync").mkdir(parents=True)
    (data / "settings.json").write_text(json.dumps({"sync_remote": "x", "sync_name": "me"}))
    picked = svc.comp.model.candidates("a")[1].ch
    (data / "sync" / "other.json").write_text(json.dumps({"uni": {picked: 50}, "bi": {}}, ensure_ascii=False))
    (data / "sync" / "me.json").write_text(json.dumps({"uni": {"日": 9999}, "bi": {}}, ensure_ascii=False))
    cjlearn_ime.PEERS._next = 0
    svc.handleRequest({"method": "onActivate", "isKeyboardOpen": True})
    assert svc.comp.model.candidates("a")[0].ch == picked      # 別台學的算進來，自己的檔不重複算
    menu = svc.handleRequest({"method": "onMenu", "id": "windows-mode-icon"})["return"]
    assert menu[-1]["text"] == "同步：還沒執行過" and menu[-1]["enabled"] is False


def test_mode_icons_bundled(svc):
    # PIME 預設安裝不含 cinbase，中／英圖示一定要是自己帶的、而且真的在安裝目錄裡
    for chinese in (True, False):
        svc.comp.chinese = chinese
        p = svc._mode_icon()
        assert os.path.isfile(p), p
        assert "cinbase" not in p
