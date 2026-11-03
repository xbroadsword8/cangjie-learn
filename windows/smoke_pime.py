"""在 Windows 上用 PIME 內建的 Python 跑：模擬按鍵訊息，確認外殼＋核心在 Python 3.8 能動。
用法：<PIME>\\python\\python3\\python.exe smoke_pime.py <含 input_methods\\cjlearn 的目錄> <PIME\\python 目錄>
學習資料寫到暫存目錄，不碰正式的 %APPDATA%\\PIME\\cjlearn。"""
import os
import shutil
import sys
import tempfile

root, pime_py = sys.argv[1], sys.argv[2]
os.environ["APPDATA"] = tempfile.mkdtemp(prefix="cjl-smoke-")
sys.path[:0] = [root, pime_py]
from input_methods.cjlearn import cjlearn_ime  # noqa: E402


class Client:
    isWindows8Above = True
    isUiLess = False


svc = cjlearn_ime.CangjieLearnTextService(Client())
svc.handleRequest({"method": "onActivate", "isKeyboardOpen": True})
down, out = set(), []


def req(method, vk):
    st = [0] * 256
    for k in down:
        st[k] = 0x80
    r = svc.handleRequest({"method": method, "charCode": vk if 0x41 <= vk <= 0x5A else 0, "keyCode": vk,
                           "repeatCount": 1, "scanCode": 0, "isExtended": False, "keyStates": st})
    out.append(r.get("commitString", ""))
    return r.get("return")


def tap(vk, *mods):
    for k in mods + (vk,):
        down.add(k)
        if req("filterKeyDown", k):
            req("onKeyDown", k)
    for k in (vk,) + tuple(reversed(mods)):
        if req("filterKeyUp", k):
            req("onKeyUp", k)
        down.discard(k)


for ch in "hqi tcp grtr ":
    tap(0x20 if ch == " " else ord(ch.upper()))
tap(0xBC, 0x11)
got = "".join(out)
print(sys.version.split()[0], "結果：", got, "通過" if got == "我恭喜，" else "失敗（期望 我恭喜，）")
learned = os.path.exists(os.path.join(os.environ["APPDATA"], "PIME", "cjlearn", "user.db"))
print("學習資料：", learned)
shutil.rmtree(os.environ["APPDATA"], ignore_errors=True)
sys.exit(0 if got == "我恭喜，" and learned else 1)
