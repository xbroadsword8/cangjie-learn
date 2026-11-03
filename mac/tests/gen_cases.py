"""產生差分測試案例：固定種子隨機按鍵序列，用 Python 版跑出預期結果 → cases.json。
整批共用一個全新 user.db（學習會影響後續排序）；每組案例用新的 Composer。
用法：python3 mac/tests/gen_cases.py [案例數]"""
import json
import random
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(ROOT))
from cjlearn.composer import Composer, CJK_PUNCT, ASCII_PUNCT  # noqa: E402
from cjlearn.model import Model  # noqa: E402

N = int(sys.argv[1]) if len(sys.argv) > 1 else 3000
rnd = random.Random(20261103)

LET = [chr(c) for c in range(97, 123)]
# 常見倉頡碼片段，讓序列較常真的組出字
SYL = ["hqi", "oiar", "tcp", "grtr", "a", "ab", "oi", "ml", "jd", "hi", "mmm", "yr", "kk", "ok", "gg"]
PUNCT = sorted(ASCII_PUNCT)
CPUNCT = sorted(CJK_PUNCT)
NAV = ["Left", "Right", "Up", "Down", "Page_Up", "Page_Down", "KP_Page_Up", "KP_Page_Down", "Home", "End", "Delete"]


def ev(k, ctrl=False, shift=False, alt=False, release=False):
    return [k, ctrl, shift, alt, release]


def gen_seq():
    out = []
    for _ in range(rnd.randint(4, 40)):
        r = rnd.random()
        if r < 0.12:  # 打一個碼後常選非第一候選：累積學習（含 bigram）
            out += [ev(c) for c in rnd.choice(SYL)]
            out.append(ev(rnd.choice("123123456789")))
        elif r < 0.30:
            out += [ev(c) for c in rnd.choice(SYL)]
        elif r < 0.42:
            out.append(ev(rnd.choice(LET)))
        elif r < 0.52:
            out.append(ev("space"))
        elif r < 0.62:
            out.append(ev(rnd.choice("0123456789")))
        elif r < 0.67:
            out.append(ev(rnd.choice(["minus", "equal"])))
        elif r < 0.72:
            out.append(ev("BackSpace"))
        elif r < 0.75:
            out.append(ev(rnd.choice(["Escape", "Return", "KP_Enter", "Tab"])))
        elif r < 0.79:
            out.append(ev(rnd.choice(NAV)))
        elif r < 0.84:
            out += [ev(rnd.choice(["Shift_L", "Shift_R"])), ev(rnd.choice(["Shift_L", "Shift_R"]), release=True)]
        elif r < 0.87:
            out.append(ev(rnd.choice(["Shift_L", "Shift_R"])))
            out.append(ev(rnd.choice(LET), shift=True))
            out.append(ev(rnd.choice(["Shift_L", "Shift_R"]), release=True))
        elif r < 0.90:
            out.append(ev(rnd.choice(LET).upper(), shift=True))
        elif r < 0.94:
            out.append(ev(rnd.choice(CPUNCT), ctrl=True, shift=rnd.random() < 0.3))
        elif r < 0.97:
            out.append(ev(rnd.choice(PUNCT), shift=rnd.random() < 0.3))
        elif r < 0.985:
            out.append(ev(rnd.choice(LET), ctrl=True))
        else:
            out.append(ev(rnd.choice(LET), alt=True))
        if rnd.random() < 0.03:  # 隨機放開事件
            out.append(ev(rnd.choice(LET + ["space", "Return"]), release=True))
    return out


tmp = Path(tempfile.mkdtemp())
model = Model(model_db=ROOT / "data" / "model.db", user_db=tmp / "user.db")
cases = []
for _ in range(N):
    keys = gen_seq()
    c = Composer(model)
    steps = []
    for k, ctrl, shift, alt, rel in keys:
        r = c.process(k, ctrl=ctrl, shift=shift, alt=alt, release=rel)
        steps.append([int(r.handled), r.commit, c.code, c.page, c.cursor, int(c.chinese),
                      "".join(x.ch for x in c.page_cands()), [x.score for x in c.page_cands()]])
    cases.append({"keys": keys, "steps": steps, "preedit": c.preedit(),
                  "page": "".join(x.ch for x in c.page_cands()), "ctx": c.ctx})
Path(__file__).with_name("cases.json").write_text(json.dumps(cases, ensure_ascii=False), encoding="utf-8")
commits = sum(1 for cs in cases for s in cs["steps"] if s[1])
print(f"{len(cases)} cases, {commits} commit steps, seed 20261103")
