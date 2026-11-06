"""學習資料同步：每台電腦把自己的次數存成 <名稱>.json，經 git 版本庫交換；輸入法讀其他台的檔案相加。

資料夾（data_dir）：放 user.db 與 settings.json 的地方（Linux ~/.local/share/cangjie-learn、
Windows %APPDATA%\\PIME\\cjlearn、Mac ~/Library/Application Support/CangjieLearn）。
  sync/        版本庫的本機複本（每台只寫自己的檔，所以不會有合併衝突）
  sync_key     這台專用的 ssh 金鑰（伺服器端限制成只能存取這個版本庫）

用法：python3 sync.py <data_dir> [--git GIT] [--ssh SSH]
輸入法本身不連網，只用 PeerWatcher 讀 sync/ 裡的檔案。
"""
import argparse
import json
import os
import socket
import sqlite3
import subprocess
import sys
import time
from pathlib import Path

try:
    from . import settings
except ImportError:   # 直接當腳本執行
    import settings

SYNC_DIR = "sync"
KEY_FILE = "sync_key"
STATUS_FILE = "sync_status.json"   # 最近一次同步的結果；輸入法選單會顯示，失敗才看得到


# --- 輸入法用：讀其他電腦的次數 ---
def read_peers(sync_dir, self_name):
    uni, bi = {}, {}
    for f in sorted(Path(sync_dir).glob("*.json")):
        if f.stem == self_name:
            continue
        try:
            d = json.loads(f.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        for src, dst in ((d.get("uni"), uni), (d.get("bi"), bi)):
            if isinstance(src, dict):
                for k, n in src.items():
                    if isinstance(k, str) and type(n) is int and n > 0:
                        dst[k] = dst.get(k, 0) + n
    return uni, bi


class PeerWatcher:
    """sync/ 有變動才重讀；最多每 interval 秒檢查一次。"""

    def __init__(self, data_dir, interval=60):
        self.data_dir = Path(data_dir)
        self.interval = interval
        self._next = 0.0
        self._sig = None

    def poll(self, model):
        now = time.monotonic()
        if now < self._next:
            return False
        self._next = now + self.interval
        name = settings.load(self.data_dir / "settings.json")["sync_name"]
        d = self.data_dir / SYNC_DIR
        try:
            sig = (name, tuple((f.name, f.stat().st_mtime_ns, f.stat().st_size) for f in sorted(d.glob("*.json"))))
        except OSError:
            sig = (name, ())
        if sig == self._sig:
            return False
        self._sig = sig
        model.set_peers(*read_peers(d, name) if name else ({}, {}))
        return True


# --- 同步程式 ---
def export(user_db, name):
    con = sqlite3.connect(str(user_db))
    try:
        uni = dict(con.execute("select ch, n from uni"))
        bi = dict(con.execute("select s, n from bi"))
    except sqlite3.OperationalError:
        uni, bi = {}, {}
    con.close()
    return {"name": name, "uni": dict(sorted(uni.items())), "bi": dict(sorted(bi.items()))}


def adopt(user_db, own_file):
    """重灌或新裝：自己的學習資料是空的、版本庫裡卻有同名的檔 → 匯入（接回以前學的）。回傳匯入筆數。"""
    con = sqlite3.connect(str(user_db))
    con.executescript(
        "create table if not exists uni (ch text primary key, n int) without rowid;"
        "create table if not exists bi (s text primary key, n int) without rowid;")
    if con.execute("select count(*) from uni").fetchone()[0] or not own_file.exists():
        con.close()
        return 0
    d = json.loads(own_file.read_text(encoding="utf-8"))
    rows = 0
    for table, items in (("uni", d.get("uni", {})), ("bi", d.get("bi", {}))):
        for k, n in items.items():
            if isinstance(k, str) and type(n) is int and n > 0:
                con.execute(f"insert into {table} values (?,?) on conflict do update set n=n+excluded.n", (k, n))
                rows += 1
    con.commit()
    con.close()
    return rows


def default_name():
    n = socket.gethostname().split(".")[0].lower()
    return "".join(c if c.isalnum() or c in "-_" else "-" for c in n) or "pc"


class Git:
    def __init__(self, repo, git, ssh, key, known_hosts):
        self.repo, self.git = repo, git
        q = lambda p: '"' + str(p).replace("\\", "/") + '"'
        self.env = dict(os.environ, GIT_SSH_COMMAND=(
            f"{q(ssh)} -i {q(key)} -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=20 "
            f"-o StrictHostKeyChecking=accept-new -o UserKnownHostsFile={q(known_hosts)}"),
            GIT_TERMINAL_PROMPT="0")

    def __call__(self, *args, check=True):
        # Windows 排程用 pythonw 跑，git.exe 是主控台程式，不加這旗標每次都會跳出 CMD 視窗（ssh 沿用同一個隱藏主控台）
        r = subprocess.run([self.git, "-C", str(self.repo), *args], env=self.env,
                           capture_output=True, text=True, encoding="utf-8", errors="replace",
                           creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
        if check and r.returncode:
            raise RuntimeError(f"git {' '.join(args)}：{r.stderr.strip()}")
        return r


def sync(data_dir, git="git", ssh="ssh", log=print):
    data_dir = Path(data_dir)
    cfg_path = data_dir / "settings.json"
    cfg = settings.load(cfg_path)
    if not cfg["sync_remote"]:
        log("沒有設定 sync_remote，不同步")
        return 0
    name = cfg["sync_name"] or default_name()
    if not cfg["sync_name"]:
        settings.update(cfg_path, sync_name=name)
    repo = data_dir / SYNC_DIR
    repo.mkdir(parents=True, exist_ok=True)
    g = Git(repo, git, ssh, data_dir / KEY_FILE, data_dir / "known_hosts")
    if not (repo / ".git").exists():
        g("init", "-q")
        g("symbolic-ref", "HEAD", "refs/heads/main")
    if g("remote", "get-url", "origin", check=False).returncode:
        g("remote", "add", "origin", cfg["sync_remote"])
    else:
        g("remote", "set-url", "origin", cfg["sync_remote"])
    own = repo / f"{name}.json"
    for attempt in range(3):
        g("fetch", "-q", "origin")
        if g("rev-parse", "-q", "--verify", "origin/main", check=False).returncode == 0:
            g("checkout", "-q", "-f", "-B", "main", "origin/main")   # 本機只有自己的檔，隨時可由 user.db 重建
        else:
            g("checkout", "-q", "-B", "main", check=False)
        n = adopt(data_dir / "user.db", own)
        if n:
            log(f"從版本庫接回 {name} 的學習資料 {n} 筆")
        data = export(data_dir / "user.db", name)
        tmp = own.with_suffix(".tmp")
        tmp.write_text(json.dumps(data, ensure_ascii=False, indent=0, sort_keys=False) + "\n", encoding="utf-8")
        tmp.replace(own)
        g("add", own.name)
        if g("diff", "--cached", "--quiet", check=False).returncode == 0:
            log(f"{name}：沒有新的學習資料；其他電腦 {len(list(repo.glob('*.json'))) - own.exists()} 台")
            return 0
        g("-c", f"user.name={name}", "-c", f"user.email={name}@cangjie-learn",
          "commit", "-q", "-m", f"{name}：{len(data['uni'])} 字、{len(data['bi'])} 組")
        if g("push", "-q", "origin", "main", check=False).returncode == 0:
            log(f"{name}：已推送（{len(data['uni'])} 字、{len(data['bi'])} 組）")
            return 0
        log("推送被拒（別台剛推過），重試")
    raise RuntimeError("推送失敗三次")


def write_status(data_dir, ok, message):
    p = Path(data_dir) / STATUS_FILE
    old = read_status(data_dir)
    st = {"ok": ok, "time": int(time.time()), "message": message,
          "last_ok": int(time.time()) if ok else old.get("last_ok", 0)}
    tmp = p.with_suffix(".tmp")
    tmp.write_text(json.dumps(st, ensure_ascii=False), encoding="utf-8")
    tmp.replace(p)


def read_status(data_dir):
    try:
        return json.loads((Path(data_dir) / STATUS_FILE).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}


def status_text(data_dir, now=None):
    """給輸入法選單用的一行字；沒設定同步回傳空字串。"""
    if not settings.load(Path(data_dir) / "settings.json")["sync_remote"]:
        return ""
    st = read_status(data_dir)
    if not st:
        return "同步：還沒執行過"
    now = time.time() if now is None else now
    def ago(t):
        m = int((now - t) // 60)
        return "剛剛" if m < 1 else f"{m} 分鐘前" if m < 60 else f"{m // 60} 小時前" if m < 2880 else f"{m // 1440} 天前"
    if st.get("ok"):
        return f"同步：{ago(st['time'])}成功"
    last = f"（上次成功 {ago(st['last_ok'])}）" if st.get("last_ok") else "（從沒成功過）"
    return f"⚠ 同步失敗{last}：{st.get('message', '')[:60]}"


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("data_dir")
    ap.add_argument("--git", default="git")
    ap.add_argument("--ssh", default="ssh")
    a = ap.parse_args(argv)
    msgs = []
    def log(m):
        print(m)
        msgs.append(m)
    try:
        rc = sync(a.data_dir, a.git, a.ssh, log=log)
        write_status(a.data_dir, True, msgs[-1] if msgs else "")
        return rc
    except Exception as e:  # noqa: BLE001 — 排程執行：原因寫進狀態檔，選單上看得到
        print(f"同步失敗：{e}", file=sys.stderr)
        write_status(a.data_dir, False, str(e))
        return 1


if __name__ == "__main__":
    sys.exit(main())
