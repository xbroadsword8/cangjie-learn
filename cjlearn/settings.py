"""使用者選項：存在學習資料旁的 settings.json（Linux／Windows／Mac 格式相同）。"""
import json
from pathlib import Path

DEFAULTS = {
    "clear_on_error": True,   # 打錯碼（沒有任何候選）按空白或數字鍵：清掉字碼，而不是停在那裡
}


def load(path):
    s = dict(DEFAULTS)
    try:
        data = json.loads(Path(path).read_text(encoding="utf-8"))
        s.update({k: v for k, v in data.items() if k in DEFAULTS and type(v) is type(DEFAULTS[k])})
    except (OSError, ValueError, AttributeError):
        pass
    return s


def save(path, s):
    p = Path(path)
    p.parent.mkdir(parents=True, exist_ok=True)
    tmp = p.with_suffix(".tmp")
    tmp.write_text(json.dumps(s, ensure_ascii=False, indent=1), encoding="utf-8")
    tmp.replace(p)
