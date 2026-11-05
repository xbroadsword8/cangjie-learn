#!/usr/bin/env python3
"""端到端測試：起一個隔離的 ibus-daemon（獨立位址、獨立 XDG 目錄，不碰使用者的 ibus 與學習資料），
建 InputContext、切到 cangjie-learn，逐鍵送事件，收集 commit-text 與「應用程式收到的鍵」。

用法：python3 tests/e2e_ibus.py
"""
import json
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path

import gi

gi.require_version("IBus", "1.0")
from gi.repository import GLib, IBus  # noqa: E402

COMPDIR = os.path.expanduser("~/.local/share/cangjie-learn/component")
M = IBus.ModifierType


def main():
    tmp = tempfile.mkdtemp(prefix="cjl-e2e-")
    sock = f"unix:path={tmp}/ibus.sock"
    env = dict(os.environ, IBUS_COMPONENT_PATH=f"/usr/share/ibus/component:{COMPDIR}",
               XDG_DATA_HOME=f"{tmp}/data", XDG_CACHE_HOME=f"{tmp}/cache",
               XDG_CONFIG_HOME=f"{tmp}/config", DISPLAY=":97", IBUS_ADDRESS=sock)
    daemon = subprocess.Popen(["ibus-daemon", "-s", "--panel=disable", "--config=disable",
                               "--emoji-extension=disable", "-t", "refresh", "-a", sock], env=env)
    try:
        time.sleep(1.5)
        os.environ.update(IBUS_ADDRESS=sock, XDG_DATA_HOME=env["XDG_DATA_HOME"])
        bus = IBus.Bus()
        assert bus.is_connected(), "連不上隔離的 ibus-daemon"
        ic = bus.create_input_context("e2e")
        committed = []
        ic.connect("commit-text", lambda _ic, t: committed.append(t.get_text()))
        ic.set_capabilities(IBus.Capabilite.PREEDIT_TEXT | IBus.Capabilite.FOCUS
                            | IBus.Capabilite.LOOKUP_TABLE)
        ic.focus_in()
        ic.set_engine("cangjie-learn")
        time.sleep(1.5)
        ctx = GLib.MainContext.default()

        def pump(sec=0.05):
            end = time.time() + sec
            while time.time() < end:
                ctx.iteration(False)
                time.sleep(0.005)

        passed = []  # 引擎沒吃掉、交給應用程式的鍵

        def key(name, mods=0):
            kv = IBus.keyval_from_name(name)
            handled = ic.process_key_event(kv, 0, mods)
            ic.process_key_event(kv, 0, mods | M.RELEASE_MASK)
            if not handled:
                passed.append(name)
            pump()

        def type_str(s):
            for ch in s:
                key({" ": "space", ",": "comma", ".": "period"}.get(ch, ch))

        def check(label, want_commit, want_passed=None):
            pump(0.2)
            got = "".join(committed)
            ok = got == want_commit and (want_passed is None or passed == want_passed)
            print(("PASS" if ok else "FAIL"), label, repr(got), passed if want_passed is not None else "")
            committed.clear(); passed.clear()
            return ok

        results = []
        print("engine =", ic.get_engine().get_name())
        type_str("hqi oiar ")
        results.append(check("基本組字 我倉", "我倉"))
        ic.reset(); key("Escape")
        committed.clear(); passed.clear()
        type_str("tcp grtr ")
        results.append(check("上文選字 恭喜", "恭喜"))
        type_str("hqi,")
        results.append(check("組字中按逗號→半形", "我,"))
        key("period")
        results.append(check("沒組字按句號→交給應用程式（半形）", "", ["period"]))
        key("comma", M.CONTROL_MASK)
        results.append(check("Ctrl+, → ，", "，"))
        key("question", M.CONTROL_MASK | M.SHIFT_MASK)
        results.append(check("Ctrl+Shift+/ → ？", "？"))
        key("c", M.CONTROL_MASK)
        results.append(check("Ctrl+C 不攔", "", ["c"]))
        key("Shift_L"); type_str("ab")
        results.append(check("單按 Shift 切英文後字母交給應用程式", "", ["Shift_L", "a", "b"]))
        key("Shift_L"); type_str("a ")
        results.append(check("再按 Shift 回中文", "日", ["Shift_L"]))
        type_str("qqqq hqi ")
        results.append(check("打錯碼按空白清掉，空白不外漏", "我", []))
        ic.property_activate("ClearOnError", IBus.PropState.UNCHECKED)
        pump(0.3)
        cfg = Path(env["XDG_DATA_HOME"]) / "cangjie-learn" / "settings.json"
        saved = json.loads(cfg.read_text()) if cfg.exists() else None
        type_str("qqqq ")
        key("Escape")
        results.append(check(f"關掉選項：打錯碼按空白停住（存檔 {saved}）", "", [])
                       and saved["clear_on_error"] is False)
        ic.property_activate("ClearOnError", IBus.PropState.CHECKED)
        pump(0.3)
        type_str("qqqq hqi ")
        results.append(check("再打開選項", "我", []))
        print(f"{sum(results)}/{len(results)} 通過")
        return 0 if all(results) else 1
    finally:
        daemon.terminate()
        daemon.wait(5)


if __name__ == "__main__":
    sys.exit(main())
