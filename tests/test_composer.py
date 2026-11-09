import pytest

from cjlearn.composer import Composer
from cjlearn.model import Model


@pytest.fixture
def comp(tmp_path):
    return Composer(Model(user_db=tmp_path / "user.db"))


def type_keys(c, keys):
    """keys：字串逐字當按鍵；回傳累計送出的文字。"""
    out = ""
    for k in keys:
        name = {" ": "space", ",": "comma", ".": "period"}.get(k, k)
        out += c.process(name).commit
    return out


def test_basic_cangjie(comp):
    assert type_keys(comp, "hqi oiar ") == "我倉"


def test_context_changes_choice(comp):
    assert type_keys(comp, "grtr ") == "嘉"          # 無上文：詞庫字頻較高的「嘉」
    comp.reset()
    assert type_keys(comp, "tcp grtr ") == "恭喜"     # 上文「恭」→「喜」


def test_learning(comp):
    # 「喜」在無上文時排第二；手動選一次之後應升到第一
    type_keys(comp, "grtr")
    assert comp.process("2").commit == "喜"
    comp.reset()
    assert type_keys(comp, "grtr ") == "喜"


def test_ascii_punct_default(comp):
    assert type_keys(comp, "hqi,") == "我,"
    assert comp.process("period").handled is False   # 沒在組字：標點交給應用程式（半形）


def test_full_punct_option(comp):
    comp.full_punct = True
    assert comp.process("comma").commit == "，"                 # 沒在組字：不按 Ctrl 也出全形
    assert type_keys(comp, "hqi") == ""
    r = comp.process("period")
    assert r.handled and r.commit == "我。"                     # 組字中：先送第一候選再接標點
    assert comp.process("question", shift=True).commit == "？"
    assert comp.process("bracketleft").commit == "「"
    assert comp.process("comma", ctrl=True).commit == "，"       # Ctrl＋標點照舊
    assert comp.process("at", shift=True).handled is False      # 不在清單的符號（@）仍交給應用程式出半形
    assert type_keys(comp, "hqi") == ""
    assert comp.process("minus").handled is True and comp.page == 0   # 組字中 - 仍是翻頁
    comp.process("Escape")
    comp.process("Shift_L"); comp.process("Shift_L", release=True)    # 切英文
    assert comp.chinese is False and comp.process("comma").handled is False


def test_full_punct_setting_default(tmp_path):
    from cjlearn import settings
    p = tmp_path / "settings.json"
    assert settings.load(p)["full_punct"] is False              # 預設關：既有使用者行為不變
    settings.update(p, full_punct=True)
    assert settings.load(p)["full_punct"] is True


def test_ctrl_punct(comp):
    assert comp.process("comma", ctrl=True).commit == "，"
    assert type_keys(comp, "hqi") == ""
    assert comp.process("period", ctrl=True).commit == "我。"
    assert comp.process("question", ctrl=True, shift=True).commit == "？"
    assert comp.process("bracketleft", ctrl=True).commit == "「"


def test_ctrl_other_keys_pass(comp):
    assert comp.process("c", ctrl=True).handled is False


def test_shift_toggle(comp):
    comp.process("Shift_L"); comp.process("Shift_L", release=True)
    assert comp.chinese is False
    assert comp.process("a").handled is False
    comp.process("Shift_L"); comp.process("Shift_L", release=True)
    assert comp.chinese is True


def test_shift_combo_does_not_toggle(comp):
    comp.process("Shift_L")
    r = comp.process("A", shift=True)
    comp.process("Shift_L", release=True)
    assert comp.chinese is True
    assert r.handled is False


def test_shift_toggle_mid_code_commits_letters(comp):
    type_keys(comp, "hq")
    comp.process("Shift_L")
    assert comp.process("Shift_L", release=True).commit == "hq"
    assert comp.code == ""


def test_backspace_and_escape(comp):
    type_keys(comp, "hqix")
    comp.process("BackSpace")
    assert comp.code == "hqi"
    comp.process("Escape")
    assert comp.code == "" and comp.cands == []


def test_select_and_page(comp):
    type_keys(comp, "a")
    first = [c.ch for c in comp.page_cands()]
    comp.process("equal")
    second = [c.ch for c in comp.page_cands()]
    assert first[0] == "日" and second and second[0] not in first
    comp.process("minus")
    assert comp.process("1").commit == "日"


def test_max_code_length(comp):
    type_keys(comp, "abcdef")
    assert comp.code == "abcde"


def test_learning_bigram(comp):
    # 「藥」後面接「孳」很罕見（字頻差很大）；手動選兩次後，同樣上文下應排第一
    for _ in range(2):
        comp.reset()
        type_keys(comp, "tvid tvid")
        assert comp.process("2").commit == "孳"
    comp.reset()
    assert type_keys(comp, "tvid tvid ") == "藥孳"


def test_clear_on_error(comp):
    # 預設：打錯碼（沒有候選）按空白清掉，空白不送出，接著照常打字
    type_keys(comp, "qqqq")
    assert comp.code == "qqqq" and comp.cands == []
    assert comp.process("space").handled
    assert comp.code == ""
    assert type_keys(comp, "hqi ") == "我"
    # 數字鍵也一樣
    type_keys(comp, "zz")
    assert comp.process("3").handled and comp.code == ""
    # 有候選時空白照常送字
    assert type_keys(comp, "hqi ") == "我"


def test_clear_on_error_off(comp):
    comp.clear_on_error = False
    type_keys(comp, "qqqq ")
    assert comp.code == "qqqq"
    comp.process("1")
    assert comp.code == "qqqq"


def test_settings_roundtrip(tmp_path):
    from cjlearn import settings
    p = tmp_path / "settings.json"
    assert settings.load(p) == settings.DEFAULTS                 # 沒有檔案 → 預設
    p.write_text("{壞掉")
    assert settings.load(p) == settings.DEFAULTS                 # 壞檔 → 預設
    settings.save(p, {"clear_on_error": False})
    assert settings.load(p)["clear_on_error"] is False
    p.write_text('{"clear_on_error": "no", "x": 1}')
    assert settings.load(p) == settings.DEFAULTS                 # 型別不對、未知鍵 → 忽略
