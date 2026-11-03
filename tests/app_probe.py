#!/usr/bin/env python3
"""在隔離的 Xvfb＋隔離 ibus-daemon 裡開真的應用程式（Chrome 或 GTK4 文字框），用 XTest 模擬實體按鍵，
看文字框實際收到什麼。不碰使用者的桌面、ibus、Chrome 設定檔與學習資料。

用法：python3 tests/app_probe.py [chrome|gtk4|nautilus]
nautilus 模式沒有文字可讀，改存截圖（路徑印在輸出裡）。
"""
import ctypes
import os
import re
import subprocess
import sys
import tempfile
import time

COMPDIR = os.path.expanduser("~/.local/share/cangjie-learn/component")
DISP = ":97"
xlib = ctypes.CDLL("libX11.so.6")
xtst = ctypes.CDLL("libXtst.so.6")
xlib.XOpenDisplay.restype = ctypes.c_void_p
xlib.XKeysymToKeycode.argtypes = [ctypes.c_void_p, ctypes.c_ulong]
xlib.XStringToKeysym.restype = ctypes.c_ulong
xlib.XFlush.argtypes = [ctypes.c_void_p]
xtst.XTestFakeKeyEvent.argtypes = [ctypes.c_void_p, ctypes.c_uint, ctypes.c_int, ctypes.c_ulong]
xtst.XTestFakeMotionEvent.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_ulong]
xtst.XTestFakeButtonEvent.argtypes = [ctypes.c_void_p, ctypes.c_uint, ctypes.c_int, ctypes.c_ulong]

GTK4_APP = r"""
import gi, sys
gi.require_version('Gtk', '4.0')
from gi.repository import Gtk, GLib
app = Gtk.Application(application_id='test.cjl.probe')
def act(a):
    w = Gtk.ApplicationWindow(application=a); w.set_default_size(600, 200)
    e = Gtk.Entry(); w.set_child(e); w.present(); e.grab_focus()
    GLib.timeout_add(300, lambda: (print('"VALUE[' + e.get_text() + ']", source', flush=True), True)[1])
app.connect('activate', act); app.run([])
"""

class XImage(ctypes.Structure):
    _fields_ = [("width", ctypes.c_int), ("height", ctypes.c_int), ("xoffset", ctypes.c_int),
                ("format", ctypes.c_int), ("data", ctypes.c_void_p), ("byte_order", ctypes.c_int),
                ("bitmap_unit", ctypes.c_int), ("bitmap_bit_order", ctypes.c_int),
                ("bitmap_pad", ctypes.c_int), ("depth", ctypes.c_int),
                ("bytes_per_line", ctypes.c_int), ("bits_per_pixel", ctypes.c_int)]


def screenshot(d, path, w=1280, h=800):
    from PIL import Image
    xlib.XDefaultRootWindow.restype = ctypes.c_ulong
    xlib.XDefaultRootWindow.argtypes = [ctypes.c_void_p]
    xlib.XGetImage.restype = ctypes.POINTER(XImage)
    xlib.XGetImage.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.c_int, ctypes.c_int,
                               ctypes.c_uint, ctypes.c_uint, ctypes.c_ulong, ctypes.c_int]
    img = xlib.XGetImage(d, xlib.XDefaultRootWindow(d), 0, 0, w, h, 0xFFFFFFFF, 2).contents
    raw = ctypes.string_at(img.data, img.bytes_per_line * h)
    Image.frombuffer("RGB", (w, h), raw, "raw", "BGRX", img.bytes_per_line, 1).save(path)
    return path


def focus_biggest_window(d):
    """沒有視窗管理員時，手動把鍵盤焦點給最大的頂層視窗（GTK4 要收到 FocusIn 才會啟用輸入法）。"""
    root = ctypes.c_ulong(); parent = ctypes.c_ulong(); children = ctypes.POINTER(ctypes.c_ulong)()
    n = ctypes.c_uint()
    xlib.XDefaultRootWindow.restype = ctypes.c_ulong
    xlib.XDefaultRootWindow.argtypes = [ctypes.c_void_p]
    xlib.XQueryTree.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.POINTER(ctypes.c_ulong),
                                ctypes.POINTER(ctypes.c_ulong),
                                ctypes.POINTER(ctypes.POINTER(ctypes.c_ulong)), ctypes.POINTER(ctypes.c_uint)]
    xlib.XQueryTree(d, xlib.XDefaultRootWindow(d), ctypes.byref(root), ctypes.byref(parent),
                    ctypes.byref(children), ctypes.byref(n))

    class Attr(ctypes.Structure):
        _fields_ = [("x", ctypes.c_int), ("y", ctypes.c_int), ("width", ctypes.c_int),
                    ("height", ctypes.c_int), ("pad", ctypes.c_byte * 256)]
    xlib.XGetWindowAttributes.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.POINTER(Attr)]
    best, area = None, 0
    for i in range(n.value):
        a = Attr()
        xlib.XGetWindowAttributes(d, children[i], ctypes.byref(a))
        if a.width * a.height > area and a.width < 5000:
            best, area = children[i], a.width * a.height
    xlib.XSetInputFocus.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.c_int, ctypes.c_ulong]
    xlib.XSetInputFocus(d, best, 2, 0)  # RevertToParent
    xlib.XFlush(d)


PAGE = """data:text/html,<textarea id=t autofocus style='width:600px;height:200px'></textarea>
<script>const t=document.getElementById('t');setInterval(()=>console.log('VALUE['+t.value+']'),300);</script>"""


def main(app="chrome"):
    tmp = tempfile.mkdtemp(prefix="cjl-chrome-")
    sock = f"unix:path={tmp}/ibus.sock"
    env = dict(os.environ, DISPLAY=DISP, IBUS_ADDRESS=sock,
               IBUS_COMPONENT_PATH=f"/usr/share/ibus/component:{COMPDIR}",
               XDG_DATA_HOME=f"{tmp}/data", XDG_CACHE_HOME=f"{tmp}/cache", XDG_CONFIG_HOME=f"{tmp}/config",
               GTK_IM_MODULE="ibus", XMODIFIERS="@im=ibus")
    env.pop("WAYLAND_DISPLAY", None)
    if os.environ.get("PROBE_NO_IMENV"):      # 模擬使用者桌面的 Chrome：沒有 GTK_IM_MODULE／XMODIFIERS
        env.pop("GTK_IM_MODULE", None); env.pop("XMODIFIERS", None)
    hold = float(os.environ.get("PROBE_HOLD", "0.05"))
    procs = []
    os.makedirs(f"{tmp}/cache/cangjie-learn", exist_ok=True)
    open(f"{tmp}/cache/cangjie-learn/debug", "w").close()   # 引擎記錄每個按鍵，方便查
    try:
        procs.append(subprocess.Popen(["Xvfb", DISP, "-screen", "0", "1280x800x24"], stderr=subprocess.DEVNULL))
        time.sleep(1)
        cfg = [] if os.environ.get("PROBE_DCONF") else ["--config=disable"]
        procs.append(subprocess.Popen(["ibus-daemon", "--panel=disable", *cfg,
                                       "--emoji-extension=disable", "-t", "refresh", "-a", sock],
                                      env=env, stderr=subprocess.DEVNULL, stdout=subprocess.DEVNULL))
        time.sleep(1.5)
        subprocess.run(["ibus", "engine", "cangjie-learn"], env=env, stderr=subprocess.DEVNULL)
        log = open(f"{tmp}/chrome.log", "w")
        if app == "nautilus":
            os.makedirs(f"{tmp}/files/資料夾", exist_ok=True)
            for n in ("報告.txt", "筆記.txt"):
                open(f"{tmp}/files/{n}", "w").close()
        page = PAGE
        if app == "xterm":   # DevDesk 用的 xterm.js：收到的資料用 console 印出
            x = os.path.expanduser("~/.hermes/projects/Hermes-DevDesk/frontend/node_modules/@xterm/xterm")
            open(f"{tmp}/xterm.html", "w").write(f"""<link rel=stylesheet href="file://{x}/css/xterm.css">
<script src="file://{x}/lib/xterm.js"></script><div id=t></div><script>
const T=window.Terminal.Terminal||window.Terminal;const t=new T();t.open(document.getElementById('t'));t.focus();
let got='';t.onData(d=>{{got+=d;}});setInterval(()=>console.log('VALUE['+got+']'),300);</script>""")
            page = f"file://{tmp}/xterm.html"
        cmd = [sys.executable, "-c", GTK4_APP] if app == "gtk4" else \
            ["dbus-run-session", "nautilus", "--new-window", f"{tmp}/files"] if app == "nautilus" else [
            "/opt/google/chrome/chrome", f"--user-data-dir={tmp}/chrome", "--no-first-run",
             "--no-default-browser-check", "--ozone-platform=x11", "--enable-logging=stderr", "--v=0",
             "--window-position=0,0", "--window-size=1200,700", "--disable-gpu", "--allow-file-access-from-files", page]
        procs.append(subprocess.Popen(cmd, env=env, stdout=log, stderr=log))
        time.sleep(6)
        subprocess.run(["ibus", "engine", "cangjie-learn"], env=env, stderr=subprocess.DEVNULL)
        d = xlib.XOpenDisplay(DISP.encode())
        assert d, "開不了 Xvfb"
        xtst.XTestFakeMotionEvent(d, -1, 200, 200, 0)
        xtst.XTestFakeButtonEvent(d, 1, 1, 0); xtst.XTestFakeButtonEvent(d, 1, 0, 0)
        xlib.XFlush(d); time.sleep(0.5)

        def kc(name):
            return xlib.XKeysymToKeycode(d, xlib.XStringToKeysym(name.encode()))

        def tap(name, mods=()):
            for m in mods:
                xtst.XTestFakeKeyEvent(d, kc(m), 1, 0)
            xtst.XTestFakeKeyEvent(d, kc(name), 1, 0); xlib.XFlush(d); time.sleep(hold)
            xtst.XTestFakeKeyEvent(d, kc(name), 0, 0); xlib.XFlush(d); time.sleep(0.05)
            for m in reversed(mods):
                xtst.XTestFakeKeyEvent(d, kc(m), 0, 0)
            xlib.XFlush(d); time.sleep(0.25)

        if app == "nautilus":
            time.sleep(2)
            focus_biggest_window(d)
            time.sleep(0.5)
            xtst.XTestFakeMotionEvent(d, -1, 600, 300, 0)   # 點檔案清單（使用者實際情境：直接打字觸發搜尋）
            xtst.XTestFakeButtonEvent(d, 1, 1, 0); xtst.XTestFakeButtonEvent(d, 1, 0, 0)
            xlib.XFlush(d); time.sleep(0.5)
            subprocess.run(["ibus", "engine", "cangjie-learn"], env=env, stderr=subprocess.DEVNULL)
            time.sleep(0.5)
            subprocess.run([sys.executable, "-c",
                            "import gi;gi.require_version('IBus','1.0');from gi.repository import IBus;"
                            "b=IBus.Bus();print('目前 IC：',b.current_input_context());"
                            "e=b.get_global_engine();print('全域引擎：',e and e.get_name())"],
                           env=env, stderr=subprocess.DEVNULL)
            r = subprocess.run(["pgrep", "-f", f"^nautilus --new-window {tmp}"], capture_output=True, text=True)
            for pid in r.stdout.split():
                maps = open(f"/proc/{pid}/maps").read()
                print("nautilus", pid, "載入 im-ibus：", "libim-ibus" in maps, "libibus：", "libibus" in maps)
            for k in "hqi":
                tap(k)
            print("截圖（打完 hqi 未送出）：", screenshot(d, f"{tmp}/n1.png"))
            tap("space")
            time.sleep(1)
            print("截圖（按空白鍵送出後）：", screenshot(d, f"{tmp}/n2.png"))
            for k in "oiar":
                tap(k)
            tap("space")
            time.sleep(1)
            print("截圖（再打 oiar 空白）：", screenshot(d, f"{tmp}/n3.png"))
            return 0
        if os.environ.get("PROBE_SEQ") == "hold":
            # 按住 Ctrl、點一下逗號，Ctrl 再多按住 0.4 秒才放（使用者的實際習慣）
            xtst.XTestFakeKeyEvent(d, kc("Control_L"), 1, 0); xlib.XFlush(d); time.sleep(0.1)
            xtst.XTestFakeKeyEvent(d, kc("comma"), 1, 0); xlib.XFlush(d); time.sleep(0.08)
            xtst.XTestFakeKeyEvent(d, kc("comma"), 0, 0); xlib.XFlush(d); time.sleep(0.4)
            xtst.XTestFakeKeyEvent(d, kc("Control_L"), 0, 0); xlib.XFlush(d)
            time.sleep(1.5)
            vals = re.findall(r'"VALUE\[(.*?)\]", source', open(f"{tmp}/chrome.log").read())
            print("Chrome 文字框最後內容：", repr(vals[-1] if vals else None), "期望：", repr("，"))
            return 0 if vals and vals[-1] == "，" else 1
        if os.environ.get("PROBE_SEQ") == "burst":
            # 按住 Ctrl 連點三下逗號，放開後立刻接著打「我」
            xtst.XTestFakeKeyEvent(d, kc("Control_L"), 1, 0); xlib.XFlush(d); time.sleep(0.1)
            for _ in range(3):
                xtst.XTestFakeKeyEvent(d, kc("comma"), 1, 0); xlib.XFlush(d); time.sleep(0.06)
                xtst.XTestFakeKeyEvent(d, kc("comma"), 0, 0); xlib.XFlush(d); time.sleep(0.06)
            xtst.XTestFakeKeyEvent(d, kc("Control_L"), 0, 0); xlib.XFlush(d)
            for k in "hqi":
                xtst.XTestFakeKeyEvent(d, kc(k), 1, 0); xtst.XTestFakeKeyEvent(d, kc(k), 0, 0); xlib.XFlush(d)
                time.sleep(0.03)
            tap("space")
            time.sleep(1.5)
            vals = re.findall(r'"VALUE\[(.*?)\]", source', open(f"{tmp}/chrome.log").read())
            print("Chrome 文字框最後內容：", repr(vals[-1] if vals else None), "期望：", repr("，，，我"))
            return 0 if vals and vals[-1] == "，，，我" else 1
        for k in "hqi":
            tap(k)
        tap("space")
        tap("comma", ["Control_L"])
        tap("period", ["Control_L"])
        tap("comma")
        tap("bracketleft", ["Control_L"])
        time.sleep(1.5)
        vals = re.findall(r'"VALUE\[(.*?)\]", source', open(f"{tmp}/chrome.log").read())
        print("Chrome 文字框最後內容：", repr(vals[-1] if vals else None))
        print("期望：", repr("我，。,「"))
        return 0 if vals and vals[-1] == "我，。,「" else 1
    finally:
        if app == "nautilus":
            subprocess.run(["pkill", "-u", str(os.getuid()), "-f", f"files {tmp}/files"], check=False)
        for p in reversed(procs):
            p.terminate()
            try:
                p.wait(5)
            except subprocess.TimeoutExpired:
                p.kill()


if __name__ == "__main__":
    sys.exit(main(*sys.argv[1:2]))
