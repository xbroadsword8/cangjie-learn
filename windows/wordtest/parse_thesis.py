"""把論文 docx 解析成依序的區塊：段落（含樣式、文字、內嵌圖、註腳、分頁）、表格。"""
import re, sys, zipfile, json
from xml.etree import ElementTree as ET
NS = {"w": "http://schemas.openxmlformats.org/wordprocessingml/2006/main",
      "a": "http://schemas.openxmlformats.org/drawingml/2006/main",
      "r": "http://schemas.openxmlformats.org/officeDocument/2006/relationships"}
W = "{%s}" % NS["w"]

def load(path):
    z = zipfile.ZipFile(path)
    rels = {}
    for m in re.finditer(r'Id="([^"]+)"[^>]*Target="([^"]+)"', z.read("word/_rels/document.xml.rels").decode()):
        rels[m.group(1)] = m.group(2)
    styles = {}
    st = ET.fromstring(z.read("word/styles.xml"))
    for s in st.findall("w:style", NS):
        n = s.find("w:name", NS)
        styles[s.get(W + "styleId")] = n.get(W + "val") if n is not None else ""
    body = ET.fromstring(z.read("word/document.xml")).find("w:body", NS)
    return z, rels, styles, body

def para(p, rels, styles):
    ps = p.find("w:pPr/w:pStyle", NS)
    sid = ps.get(W + "val") if ps is not None else ""
    items = []   # ("t", text) / ("img", target) / ("fn",) / ("pb",) / ("field", instr)
    in_field = False
    for el in p.iter():
        tag = el.tag.split("}")[1]
        if tag == "fldChar":
            t = el.get(W + "fldCharType")
            if t == "begin": in_field = True; instr = ""
            elif t == "separate": items.append(("field", instr.strip())); in_field = "res"
            elif t == "end": in_field = False
        elif tag == "instrText":
            instr += el.text or ""
        elif tag == "t" and el.text:
            if in_field == "res":  # 功能變數結果（頁碼、編號）照樣算文字，但標記
                items.append(("ft", el.text))
            elif not in_field:
                items.append(("t", el.text))
        elif tag == "blip":
            items.append(("img", rels.get(el.get("{%s}embed" % NS["r"]), "")))
        elif tag == "footnoteReference":
            items.append(("fn", el.get(W + "id")))
        elif tag == "br" and el.get(W + "type") == "page":
            items.append(("pb",))
        elif tag == "sectPr":
            items.append(("sect",))
    return {"k": "p", "style": styles.get(sid, sid), "items": items}

def blocks(path):
    z, rels, styles, body = load(path)
    out = []
    for el in body:
        tag = el.tag.split("}")[1]
        if tag == "p":
            out.append(para(el, rels, styles))
        elif tag == "tbl":
            rows = []
            for tr in el.findall("w:tr", NS):
                rows.append(["".join(t.text or "" for t in tc.iter(W + "t")) for tc in tr.findall("w:tc", NS)])
            out.append({"k": "tbl", "rows": rows})
    return z, out

def ptext(b):
    return "".join(x[1] for x in b["items"] if x[0] in ("t", "ft"))

if __name__ == "__main__":
    z, bl = blocks(sys.argv[1])
    cjk = lambda s: sum(1 for c in s if "一" <= c <= "鿿")
    cur = None; stat = {}
    for i, b in enumerate(bl):
        if b["k"] == "p" and re.match(r"heading 1|標題 1", b["style"], re.I):
            cur = f"{i}:{ptext(b)[:30]}"; stat[cur] = [0, 0, 0, 0, 0]
        if cur is None: continue
        s = stat[cur]
        if b["k"] == "p":
            s[0] += cjk(ptext(b)); s[1] += sum(1 for x in b["items"] if x[0] == "img")
            s[3] += sum(1 for x in b["items"] if x[0] == "fn"); s[4] += sum(1 for x in b["items"] if x[0] == "field" and x[1].startswith("CITATION"))
        else:
            s[2] += 1
    for k, v in stat.items(): print(k, "中文字=%d 圖=%d 表=%d 註腳=%d 引用=%d" % tuple(v))
