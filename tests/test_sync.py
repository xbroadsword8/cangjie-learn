"""學習資料同步：用本機的 bare 版本庫模擬伺服器，兩、三台「電腦」各自的 data_dir。"""
import json
import subprocess

import pytest

from cjlearn import settings, sync
from cjlearn.composer import Composer
from cjlearn.model import Model


@pytest.fixture
def remote(tmp_path):
    r = tmp_path / "server" / "learn.git"
    subprocess.run(["git", "init", "-q", "--bare", "-b", "main", str(r)], check=True)
    return str(r)


def machine(tmp_path, name, remote, sync_name=""):
    d = tmp_path / name
    d.mkdir()
    settings.save(d / "settings.json", dict(settings.DEFAULTS, sync_remote=remote, sync_name=sync_name))
    return d


def type_and_learn(d, keys):
    m = Model(user_db=d / "user.db")
    c = Composer(m)
    for k in keys:
        c.process({" ": "space"}.get(k, k))
    m.user.close()


def test_two_machines_share(tmp_path, remote):
    a = machine(tmp_path, "a", remote, "pc-a")
    b = machine(tmp_path, "b", remote, "pc-b")
    type_and_learn(a, "a2a2a2")            # a 台：「日」那頁選第 2 個，選三次
    assert sync.sync(a, log=lambda *_: None) == 0
    assert sync.sync(b, log=lambda *_: None) == 0
    assert (b / "sync" / "pc-a.json").exists() and (b / "sync" / "pc-b.json").exists()

    mb = Model(user_db=b / "user.db")
    picked = mb.candidates("a")[1].ch      # a 台選的那個字（b 台沒學過，排序同全新的）
    score = lambda m: next(c.score for c in m.candidates("a") if c.ch == picked)
    before = score(mb)
    w = sync.PeerWatcher(b, interval=0)
    assert w.poll(mb)
    assert not w.poll(mb)                  # 沒變動不重讀
    assert score(mb) > before
    assert score(mb) == pytest.approx(score(Model(user_db=a / "user.db")))   # b 台照 a 台學的算分

    assert sync.sync(a, log=lambda *_: None) == 0           # a 再同步，拿到 b 的檔
    assert (a / "sync" / "pc-b.json").exists()


def test_own_file_not_counted_twice(tmp_path, remote):
    a = machine(tmp_path, "a", remote, "pc-a")
    type_and_learn(a, "a2")
    sync.sync(a, log=lambda *_: None)
    uni, bi = sync.read_peers(a / "sync", "pc-a")
    assert uni == {} and bi == {}


def test_reinstall_adopts_own_history(tmp_path, remote):
    a = machine(tmp_path, "a", remote, "pc-a")
    type_and_learn(a, "a2a2")
    sync.sync(a, log=lambda *_: None)
    before = sync.export(a / "user.db", "pc-a")
    a2 = machine(tmp_path, "a-reinstalled", remote, "pc-a")   # 重灌：同名、user.db 是空的
    msgs = []
    sync.sync(a2, log=msgs.append)
    assert any("接回" in m for m in msgs)
    assert sync.export(a2 / "user.db", "pc-a") == before
    sync.sync(a2, log=msgs.append)                            # 再跑一次不會重複匯入
    assert sync.export(a2 / "user.db", "pc-a") == before


def test_concurrent_push_retries(tmp_path, remote):
    a = machine(tmp_path, "a", remote, "pc-a")
    b = machine(tmp_path, "b", remote, "pc-b")
    type_and_learn(a, "a2")
    type_and_learn(b, "a3")
    sync.sync(a, log=lambda *_: None)
    sync.sync(b, log=lambda *_: None)
    type_and_learn(a, "hqi ")
    type_and_learn(b, "oiar ")
    sync.sync(a, log=lambda *_: None)
    msgs = []
    sync.sync(b, log=msgs.append)          # b 的本機複本落後：fetch 後重建再推，不衝突
    sync.sync(a, log=lambda *_: None)
    for d in (a, b):
        names = sorted(p.stem for p in (d / "sync").glob("*.json"))
        assert names == ["pc-a", "pc-b"]
    assert "我" in json.loads((b / "sync" / "pc-a.json").read_text())["uni"]


def test_name_defaults_to_hostname_and_saved(tmp_path, remote):
    a = machine(tmp_path, "a", remote)
    sync.sync(a, log=lambda *_: None)
    name = settings.load(a / "settings.json")["sync_name"]
    assert name == sync.default_name() and (a / "sync" / f"{name}.json").exists()


def test_no_remote_does_nothing(tmp_path):
    d = tmp_path / "x"
    d.mkdir()
    assert sync.sync(d, log=lambda *_: None) == 0
    assert not (d / "sync").exists()


def test_bad_peer_files_ignored(tmp_path):
    d = tmp_path / "s"
    d.mkdir()
    (d / "bad.json").write_text("{壞")
    (d / "odd.json").write_text(json.dumps({"uni": {"日": "3", "月": -1, "金": 2}, "bi": []}))
    assert sync.read_peers(d, "me") == ({"金": 2}, {})


def test_settings_update_keeps_other_keys(tmp_path):
    p = tmp_path / "settings.json"
    settings.update(p, sync_name="pc-a")
    settings.update(p, clear_on_error=False)
    s = settings.load(p)
    assert s["sync_name"] == "pc-a" and s["clear_on_error"] is False


def test_status_shown_and_failure_visible(tmp_path, remote):
    a = machine(tmp_path, "a", remote, "pc-a")
    assert sync.status_text(a) == "同步：還沒執行過"
    assert sync.main([str(a)]) == 0
    assert sync.status_text(a).endswith("成功")
    settings.update(a / "settings.json", sync_remote=str(tmp_path / "沒有這個庫.git"))   # 注入故障
    assert sync.main([str(a)]) == 1
    t = sync.status_text(a, now=sync.read_status(a)["time"] + 3 * 3600)
    assert t.startswith("⚠ 同步失敗（上次成功 3 小時前）")
    d = tmp_path / "nosync"
    d.mkdir()
    assert sync.status_text(d) == ""
