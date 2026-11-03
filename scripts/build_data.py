#!/usr/bin/env python3
"""建 data/model.db：倉頡三代碼表（取自 ibus-table）＋ libchewing 字詞頻。

用法：python3 scripts/build_data.py
來源：
  /usr/share/ibus-table/tables/cangjie3.db（碼表與原始排序）
  data/raw/tsi.csv、data/raw/word.csv（libchewing-data，LGPL-2.1-or-later）
"""
import csv
import math
import sqlite3
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TABLE = Path("/usr/share/ibus-table/tables/cangjie3.db")
RAW = ROOT / "data" / "raw"
OUT = ROOT / "data" / "model.db"
MAX_N = 4  # 詞內子字串最長取到 4 字（3 字上文＋候選字）


def read_freq_csv(path):
    freq = defaultdict(int)
    with open(path, encoding="utf-8") as f:
        for row in csv.reader(f):
            if not row or row[0].startswith("#") or len(row) < 2:
                continue
            try:
                freq[row[0]] += int(row[1])
            except ValueError:
                continue
    return freq


def main():
    src = sqlite3.connect(TABLE)
    codes = src.execute(
        "select tabkeys, phrase, freq from phrases "
        "where tabkeys <> '' and tabkeys not glob '*[^a-z]*'"
    ).fetchall()

    chars = read_freq_csv(RAW / "word.csv")
    words = read_freq_csv(RAW / "tsi.csv")
    # 單字頻：word.csv 與 tsi.csv 的單字詞取大者
    for w, n in words.items():
        if len(w) == 1:
            chars[w] = max(chars[w], n)

    # 詞內 n-gram（2..MAX_N 字）累計詞頻：「上文＋候選字」若是某詞的一段就加分
    ngram = defaultdict(int)
    for w, n in words.items():
        if len(w) < 2 or n <= 0:
            continue
        for i in range(len(w)):
            for j in range(i + 2, min(len(w), i + MAX_N) + 1):
                ngram[w[i:j]] += n

    OUT.unlink(missing_ok=True)
    db = sqlite3.connect(OUT)
    db.executescript(
        """
        create table code (code text, ch text, rank int);
        create index code_code on code(code);
        create table uni (ch text primary key, freq int) without rowid;
        create table ngram (s text primary key, freq int) without rowid;
        create table meta (k text primary key, v text);
        """
    )
    # rank：碼表原始排序（freq 大者在前），同分時保留表內順序
    by_code = defaultdict(list)
    for i, (k, ch, f) in enumerate(codes):
        by_code[k].append((-f, i, ch))
    rows = []
    for k, lst in by_code.items():
        for r, (_, _, ch) in enumerate(sorted(lst)):
            rows.append((k, ch, r))
    db.executemany("insert into code values (?,?,?)", rows)
    db.executemany("insert into uni values (?,?)", ((c, n) for c, n in chars.items() if len(c) == 1))
    db.executemany("insert into ngram values (?,?)", ngram.items())
    db.executemany(
        "insert into meta values (?,?)",
        [("source", "ibus-table cangjie3 + libchewing-data tsi/word"), ("max_n", str(MAX_N))],
    )
    db.commit()
    print(f"codes={len(rows)} uni={len(chars)} ngram={len(ngram)} -> {OUT}")


if __name__ == "__main__":
    main()
