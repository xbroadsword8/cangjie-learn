"""選字模型：碼表查詢＋上下文排序＋使用者學習。不依賴 IBus，可單獨測試。"""
import math
import os
import sqlite3
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MODEL_DB = ROOT / "data" / "model.db"
USER_DB = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local" / "share")) / "cangjie-learn" / "user.db"

CTX_LEN = 3                              # 往前看幾個字
W_NGRAM = {1: 1.5, 2: 2.0, 3: 2.5}       # 上文長度 k → 詞內 n-gram 權重
W_USER_BI = 3.0                          # 使用者「前一字→此字」次數
W_USER_UNI = 2.0                         # 使用者選過此字的次數
CORRECTION_BOOST = 3                     # 不是第一候選卻被選中：算 3 次（使用者在糾正排序）
W_CONTAINED = 0.3                        # 單字頻＝單字詞頻＋0.3×含此字的詞總頻
MAX_COMPLETIONS = 60
DECIDE_RATIO = 10                        # 上文 bigram 比同碼其他字的 bigram 大這麼多倍 → 這次選字由上文決定


class Candidate:
    __slots__ = ("ch", "code", "exact", "score")

    def __init__(self, ch, code, exact, score):
        self.ch, self.code, self.exact, self.score = ch, code, exact, score

    def __repr__(self):
        return f"{self.ch}({self.code},{self.score:.1f})"


class Model:
    def __init__(self, model_db=MODEL_DB, user_db=USER_DB):
        self.db = sqlite3.connect(str(model_db), check_same_thread=False)
        self._uni = dict(self.db.execute("select ch, freq from uni"))
        Path(user_db).parent.mkdir(parents=True, exist_ok=True)
        self.user = sqlite3.connect(str(user_db), check_same_thread=False)
        self.user.executescript(
            "create table if not exists uni (ch text primary key, n int) without rowid;"
            "create table if not exists bi (s text primary key, n int) without rowid;"
        )
        self._user_uni = dict(self.user.execute("select ch, n from uni"))
        self._user_bi = dict(self.user.execute("select s, n from bi"))
        self._peer_uni, self._peer_bi = {}, {}   # 其他電腦學到的次數（sync.py），選字時與自己的相加
        self._ngram_cache = {}
        self._decides_cache = {}
        self._explained = self._count_explained()

    # --- 查詢 ---
    def _ngram(self, s):
        v = self._ngram_cache.get(s)
        if v is None:
            row = self.db.execute("select freq from ngram where s=?", (s,)).fetchone()
            v = row[0] if row else 0
            if len(self._ngram_cache) > 200_000:
                self._ngram_cache.clear()
            self._ngram_cache[s] = v
        return v

    def _decides(self, s):
        """bigram s（前一字＋此字）在詞庫裡遠多於同碼其他字的同位置 bigram：選這個字是上文決定的，
        不代表使用者偏好這個字（例：「自己」的己、「而已」的已）。"""
        v = self._decides_cache.get(s)
        if v is None:
            p, ch = s[:-1], s[-1]
            f = self._ngram(s)
            v = f > 0
            if v:
                for (code,) in self.db.execute("select code from code where ch=?", (ch,)).fetchall():
                    for (r,) in self.db.execute("select ch from code where code=?", (code,)).fetchall():
                        if r != ch and self._ngram(p + r) * DECIDE_RATIO > f:
                            v = False
                            break
                    if not v:
                        break
            self._decides_cache[s] = v
        return v

    def _count_explained(self):
        """每個字有幾次學習是上文決定的；單字偏好扣掉這部分，免得「自己」打多了，句首的「已經」也變成「己經」。"""
        e = {}
        for d in (self._user_bi, self._peer_bi):
            for s, n in d.items():
                if self._decides(s):
                    e[s[-1]] = e.get(s[-1], 0) + n
        return e

    def score(self, ch, ctx):
        s = math.log1p(self._uni.get(ch, 0))
        for k in (1, 2, 3):
            if len(ctx) >= k:
                f = self._ngram(ctx[-k:] + ch)
                if f:
                    s += W_NGRAM[k] * math.log1p(f)
        if ctx:
            k = ctx[-1] + ch
            s += W_USER_BI * math.log1p(self._user_bi.get(k, 0) + self._peer_bi.get(k, 0))
        u = self._user_uni.get(ch, 0) + self._peer_uni.get(ch, 0) - self._explained.get(ch, 0)
        s += W_USER_UNI * math.log1p(max(0, u))
        return s

    def candidates(self, code, ctx=""):
        """完整碼命中的字排前面；其後是以 code 為前綴的補完字。兩組各自依分數排序。"""
        if not code:
            return []
        ctx = ctx[-CTX_LEN:]
        exact = [Candidate(ch, c, True, self.score(ch, ctx)) for c, ch in
                 self.db.execute("select code, ch from code where code=? order by rank", (code,))]
        exact.sort(key=lambda c: -c.score)  # 穩定排序：同分保留碼表原序
        seen = {c.ch for c in exact}
        comp = []
        for c, ch in self.db.execute(
            "select code, ch from code where code > ? and code < ? order by length(code), rank",
            (code, code + "{"),
        ):
            if ch not in seen:
                seen.add(ch)
                comp.append(Candidate(ch, c, False, self.score(ch, ctx)))
        comp.sort(key=lambda c: -c.score)
        return exact + comp[:MAX_COMPLETIONS]

    def set_peers(self, uni, bi):
        self._peer_uni, self._peer_bi = uni, bi
        self._explained = self._count_explained()

    # --- 學習 ---
    def learn(self, ch, prev="", corrected=False):
        n = CORRECTION_BOOST if corrected else 1
        self._user_uni[ch] = self._user_uni.get(ch, 0) + n
        self.user.execute("insert into uni values (?,?) on conflict(ch) do update set n=n+?", (ch, n, n))
        if prev:
            s = prev[-1] + ch
            self._user_bi[s] = self._user_bi.get(s, 0) + n
            if self._decides(s):
                self._explained[ch] = self._explained.get(ch, 0) + n
            self.user.execute("insert into bi values (?,?) on conflict(s) do update set n=n+?", (s, n, n))
        self.user.commit()
