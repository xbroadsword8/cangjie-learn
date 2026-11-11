"""Rust 版 cjlearn-sync 與 Python 版 sync.py 的輸出必須逐位元組相同（兩者會推同一個版本庫）。
執行檔位置：環境變數 CJLEARN_SYNC_BIN，或 windows/tsf/target/release/cjlearn-sync；找不到就略過。"""
import json
import os
import shutil
import sqlite3
import subprocess
from pathlib import Path

import pytest

from cjlearn import settings, sync

ROOT = Path(__file__).resolve().parent.parent
BIN = Path(os.environ.get("CJLEARN_SYNC_BIN", ROOT / "windows/tsf/target/release/cjlearn-sync"))
pytestmark = pytest.mark.skipif(not BIN.exists(), reason="cjlearn-sync 未編譯")


@pytest.fixture
def mk_remote(tmp_path):
    def f(tag):
        r = tmp_path / f"srv-{tag}" / "learn.git"
        subprocess.run(["git", "init", "-q", "--bare", "-b", "main", str(r)], check=True)
        return str(r)
    return f


def machine(tmp_path, tag, remote, name="pc-x", rows=True):
    d = tmp_path / tag
    d.mkdir()
    settings.save(d / "settings.json", dict(settings.DEFAULTS, sync_remote=remote, sync_name=name))
    if rows:
        con = sqlite3.connect(d / "user.db")
        con.executescript("create table uni (ch text primary key, n int) without rowid;"
                          "create table bi (s text primary key, n int) without rowid;")
        con.executemany("insert into uni values (?,?)", [("日", 3), ("我", 12), ("a\"b\\c", 1), ("\x01\t😀", 7), ("z", 2)])
        con.executemany("insert into bi values (?,?)", [("我日", 4), ("日我", 1)])
        con.commit()
        con.close()
    return d


def rust(d, *extra):
    return subprocess.run([str(BIN), str(d), "--ssh", "C:\\fake\\ssh.exe", *extra], capture_output=True, text=True, encoding="utf-8")


def status(d):
    s = json.loads((d / "sync_status.json").read_text(encoding="utf-8"))
    s.pop("time"), s.pop("last_ok")
    return s


def test_byte_identical_output(tmp_path, mk_remote):
    py = machine(tmp_path, "py", mk_remote("py"))
    rs = machine(tmp_path, "rs", mk_remote("rs"))
    assert sync.main([str(py)]) == 0
    r = rust(rs)
    assert r.returncode == 0, r.stderr
    assert (py / "sync/pc-x.json").read_bytes() == (rs / "sync/pc-x.json").read_bytes()
    a = (py / "sync_status.json").read_text(encoding="utf-8")
    b = (rs / "sync_status.json").read_text(encoding="utf-8")
    import re
    norm = lambda s: re.sub(r'"(time|last_ok)": \d+', r'"\1": 0', s)
    assert norm(a) == norm(b)
    # 第二次（沒新資料）訊息也相同
    sync.main([str(py)]), rust(rs)
    assert status(py) == status(rs) and "沒有新的學習資料" in status(rs)["message"]
    # 空表：{} 的寫法也要相同
    py2 = machine(tmp_path, "py2", mk_remote("py2"), rows=False)
    rs2 = machine(tmp_path, "rs2", mk_remote("rs2"), rows=False)
    sync.main([str(py2)]), rust(rs2)
    assert (py2 / "sync/pc-x.json").read_bytes() == (rs2 / "sync/pc-x.json").read_bytes()
    assert (rs2 / "sync/pc-x.json").read_text() == '{\n"name": "pc-x",\n"uni": {},\n"bi": {}\n}\n'


def test_alternating_machines_and_commit_message(tmp_path, mk_remote):
    remote = mk_remote("shared")
    a = machine(tmp_path, "a", remote, "pc-a")
    b = machine(tmp_path, "b", remote, "pc-b")
    assert sync.main([str(a)]) == 0
    assert rust(b).returncode == 0
    con = sqlite3.connect(a / "user.db"); con.execute("update uni set n=n+1"); con.commit(); con.close()
    assert sync.main([str(a)]) == 0                       # a 落後 b 的推送後再推：不衝突
    con = sqlite3.connect(b / "user.db"); con.execute("update uni set n=n+5"); con.commit(); con.close()
    assert rust(b).returncode == 0
    assert sync.main([str(a)]) == 0
    assert sorted(p.stem for p in (a / "sync").glob("*.json")) == ["pc-a", "pc-b"]
    log = subprocess.run(["git", "-C", str(a / "sync"), "log", "--format=%an|%ae|%s", "origin/main"], capture_output=True, text=True).stdout.splitlines()
    assert "pc-b|pc-b@cangjie-learn|pc-b：5 字、2 組" in log
    assert "pc-a|pc-a@cangjie-learn|pc-a：5 字、2 組" in log


def test_adopt_reinstall(tmp_path, mk_remote):
    remote = mk_remote("adopt")
    a = machine(tmp_path, "a", remote, "pc-a")
    assert rust(a).returncode == 0
    before = sync.export(a / "user.db", "pc-a")
    a2 = machine(tmp_path, "a2", remote, "pc-a", rows=False)
    r = rust(a2)
    assert r.returncode == 0 and "從版本庫接回 pc-a 的學習資料 7 筆" in r.stdout
    assert sync.export(a2 / "user.db", "pc-a") == before
    assert "接回" not in rust(a2).stdout                 # 不重複匯入


def test_no_remote_and_default_name_and_failure(tmp_path):
    d = tmp_path / "x"; d.mkdir()
    r = rust(d)
    assert r.returncode == 0 and r.stdout.strip() == "沒有設定 sync_remote，不同步"
    assert not (d / "sync").exists() and status(d)["ok"] is True
    # 沒設名稱 → 用主機名並存回 settings
    e = tmp_path / "y"; e.mkdir()
    settings.save(e / "settings.json", dict(settings.DEFAULTS, sync_remote=str(tmp_path / "nonexistent.git")))
    r = rust(e)
    assert r.returncode == 1 and "同步失敗：git fetch -q origin：" in r.stderr
    assert settings.load(e / "settings.json")["sync_name"] == sync.default_name()
    st = status(e)
    assert st["ok"] is False and st["message"].startswith("git fetch -q origin：")
    assert rust(e, "--bogus").returncode == 2
