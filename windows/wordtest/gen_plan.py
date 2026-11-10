"""論文片段 → Word 重打操作清單（plan.json）＋需要的圖片。用法：gen_plan.py <thesis.docx> <libchewing data/raw> <輸出目錄>"""
import csv, json, re, sys, zipfile, collections
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
from parse_thesis import blocks, ptext

docx, raw, outdir = sys.argv[1], Path(sys.argv[2]), Path(sys.argv[3])
RANGES = [(20, 33), (172, 274)]          # 摘要；第一章＋第二章前段（約 5,800 字）
CHUNK = 8                               # 新酷音一次最多組幾個字再按 Enter 送出

# --- 注音 ---
ZK = dict(zip("ㄅㄆㄇㄈㄉㄊㄋㄌㄍㄎㄏㄐㄑㄒㄓㄔㄕㄖㄗㄘㄙㄧㄨㄩㄚㄛㄜㄞㄟㄠㄢㄣㄦ",
              "1 q a z 2 w s x e d c r f v 5 t g b y h n u j m 8 i k 9 o l 0 p oem_minus".split()))
ZK.update({"ㄝ": "oem_comma", "ㄡ": "oem_period", "ㄤ": "oem_1", "ㄥ": "oem_2"})
TONE = {"ˊ": "6", "ˇ": "3", "ˋ": "4", "˙": "7"}
def syl_keys(z):
    tone = next((TONE[c] for c in z if c in TONE), "space")
    return [ZK[c] for c in z if c in ZK] + [tone]

phr = collections.defaultdict(list)    # 詞 → [(頻率, 讀音)]
def rows(f):
    for line in open(f, encoding="utf-8"):
        if line.startswith("#"): continue
        r = line.rstrip("\n").split(",")
        if len(r) >= 3: yield r
for w, f, z in rows(raw / "tsi.csv"):
    if all("一" <= c <= "鿿" for c in w):
        phr[w].append((int(f or 0), z.split(" ")))
single = {}
for w, f, z in rows(raw / "word.csv"):
    single.setdefault(w, z)
def readings(text):
    """最長詞比對決定破音字讀音；回傳每字的注音（找不到為 None）。"""
    out, i = [], 0
    while i < len(text):
        for L in range(min(6, len(text) - i), 0, -1):
            w = text[i:i + L]
            if w in phr:
                out += max(phr[w])[1]; i += L; break
        else:
            out.append(single.get(text[i])); i += 1
    return out

# 新酷音（windows-chewing-tsf 26.11.724 預設）實測：Shift＋標點出全形，[ ] ' 直接出「」、；字先進組字區，按 Enter 送出
PUNCT = {"，": "shift+oem_comma", "。": "shift+oem_period", "：": "shift+oem_1", "？": "shift+oem_2", "；": "shift+oem_7",
         "『": "shift+oem_4", "』": "shift+oem_6", "！": "shift+1", "（": "shift+9", "）": "shift+0", "～": "shift+oem_3",
         "「": "oem_4", "」": "oem_6", "、": "oem_7", "——": "shift+oem_minus shift+oem_minus"}   # 《》……沒有直接的鍵，走 COM
def text_ops(s):
    """一段文字 → zh／punct／ascii／com 操作。"""
    ops, buf, keys = [], "", []
    def flush():
        nonlocal buf, keys
        if buf:
            ops.append({"op": "zh", "text": buf, "n": len(buf), "keys": " ".join(keys + ["return"])})
        buf, keys = "", []
    i = 0
    while i < len(s):
        c = s[i]
        two = s[i:i + 2]
        if "一" <= c <= "鿿":
            j = i
            while j < len(s) and "一" <= s[j] <= "鿿": j += 1
            run = s[i:j]
            for ch, z in zip(run, readings(run)):
                if z is None:
                    flush(); ops.append({"op": "com", "text": ch})
                else:
                    buf += ch; keys += syl_keys(z)
                    if len(buf) >= CHUNK: flush()
            i = j; continue
        flush()
        if two in PUNCT:
            ops.append({"op": "punct", "ch": two, "keys": PUNCT[two] + " return"}); i += 2; continue
        if c in PUNCT:
            ops.append({"op": "punct", "ch": c, "keys": PUNCT[c] + " return"}); i += 1; continue
        if " " <= c <= "~":
            j = i
            while j < len(s) and " " <= s[j] <= "~": j += 1
            ops.append({"op": "ascii", "text": s[i:j]}); i = j; continue
        ops.append({"op": "com", "text": c}); i += 1
    flush()
    # 相鄰 com 合併
    merged = []
    for o in ops:
        if merged and o["op"] == "com" and merged[-1]["op"] == "com": merged[-1]["text"] += o["text"]
        else: merged.append(o)
    return merged

z, bl = blocks(docx)
fn_text = {}
fx = z.read("word/footnotes.xml").decode("utf-8")
for m in re.finditer(r'<w:footnote [^>]*w:id="(-?\d+)"[^>]*>(.*?)</w:footnote>', fx, re.S):
    fn_text[m.group(1)] = "".join(re.findall(r"<w:t[^>]*>([^<]*)</w:t>", m.group(2))).strip()

STYLE = {"heading 1": "h1", "heading 2": "h2", "heading 3": "h3", "caption": "caption", "Quote": "quote", "List Paragraph": "list"}
plan, imgs, caps = [], [], {}           # caps：論文圖號（如「圖 2 - 11」）→ 本文件第幾個「圖」
cap_count = collections.Counter()
img_methods = ["addpic", "clip", "snip", "copy"]
para_n = 0

def para_ops(b):
    """一個段落的 items → 操作；功能變數（CITATION／REF）換成對應操作，結果文字不重打。"""
    ops, text, skip = [], "", False
    def flush_text():
        nonlocal text
        if text: ops.extend(text_ops(text)); text = ""
    for it in b["items"]:
        k = it[0]
        if k == "field":
            flush_text()
            instr = it[1]
            skip = True
            m = re.match(r"CITATION\s+(\S+)", instr)
            if m: ops.append({"op": "citation", "tag": m.group(1)}); continue
            if re.match(r"(REF|PAGEREF)\s", instr): ops.append({"op": "xref_pending"}); continue
            skip = False      # 其他功能變數（SEQ 等）的結果照樣當文字
            continue
        if k == "ft":
            if skip:
                if ops and ops[-1]["op"] == "citation" and "result" not in ops[-1]: ops[-1]["result"] = it[1]
                elif ops and ops[-1]["op"] == "xref_pending": ops[-1]["result"] = ops[-1].get("result", "") + it[1]
                continue
            text += it[1]; continue
        skip = False
        if k == "t": text += it[1]
        elif k == "img":
            flush_text(); f = it[1].split("/")[-1]; imgs.append(f)
            ops.append({"op": "img", "file": f, "method": img_methods[len(imgs) % 4]})
        elif k == "fn":
            flush_text(); ops.append({"op": "footnote", "ops": text_ops(fn_text.get(it[1], "註腳"))})
        elif k == "pb":
            flush_text(); ops.append({"op": "pagebreak"})
    flush_text()
    # xref：對到已建立的圖說就插交互參照，否則把顯示文字打出來
    out = []
    for o in ops:
        if o["op"] == "xref_pending":
            r = re.sub(r"\s+", " ", o.get("result", "")).strip()
            if r in caps: out.append({"op": "xref", "label": "圖" if r.startswith("圖") else "表", "idx": caps[r], "text": r})
            else: out.extend(text_ops(o.get("result", "")))
        else: out.append(o)
    return out

for ri, (a, bnd) in enumerate(RANGES):
    if ri: plan.append({"op": "section"})
    head = ptext(bl[a]).strip()
    plan.append({"op": "header", "ops": text_ops(head)})
    for i in range(a, bnd):
        b = bl[i]
        if b["k"] == "tbl":
            plan.append({"op": "table", "rows": [[text_ops(c.strip()) for c in r] for r in b["rows"]]})
            continue
        st = STYLE.get(b["style"], "normal")
        t = ptext(b)
        if st == "caption":
            m = re.match(r"\s*([圖表])\s*([\d\s\-－]+?)\s*[　 ]+(.*)", t)
            if m:
                label, num, title = m.group(1), re.sub(r"\s+", " ", m.group(2)).strip(), m.group(3)
                cap_count[label] += 1; caps[f"{label} {num}"] = cap_count[label]
                plan.append({"op": "caption", "label": label, "ops": text_ops(title)})
                continue
        if not t.strip() and not any(x[0] in ("img", "fn", "pb") for x in b["items"]):
            continue
        plan.append({"op": "style", "name": st})
        plan += para_ops(b)
        plan.append({"op": "para"})
        para_n += 1
        if para_n % 6 == 0 and st == "normal": plan.append({"op": "ruler"})
plan.append({"op": "toc"})

outdir.mkdir(parents=True, exist_ok=True)
(outdir / "media").mkdir(exist_ok=True)
for f in set(imgs):
    (outdir / "media" / f).write_bytes(z.read("word/media/" + f))
(outdir / "plan.json").write_text(json.dumps(plan, ensure_ascii=False), encoding="utf-8-sig")

def walk(ops):
    for o in ops:
        yield o
        for k in ("ops",):
            if k in o: yield from walk(o[k])
        if o["op"] == "table":
            for r in o["rows"]:
                for c in r: yield from walk(c)
allops = list(walk(plan))
cnt = collections.Counter(o["op"] for o in allops)
print("操作數:", dict(cnt))
print("中文字（經輸入法）:", sum(o["n"] for o in allops if o["op"] == "zh"), " 標點:", cnt["punct"],
      " COM 插入字元:", sum(len(o["text"]) for o in allops if o["op"] == "com"), " 英數:", sum(len(o["text"]) for o in allops if o["op"] == "ascii"))
print("圖片方式:", collections.Counter(o["method"] for o in allops if o["op"] == "img"))
print("COM 插入的字：", "".join(sorted(set("".join(o["text"] for o in allops if o["op"] == "com"))))[:80])
