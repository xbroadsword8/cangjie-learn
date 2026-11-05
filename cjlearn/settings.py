"""使用者選項：存在學習資料旁的 settings.json（Linux／Windows／Mac 格式相同）。"""
import json
from pathlib import Path

DEFAULTS = {
    "clear_on_error": True,   # 打錯碼（沒有任何候選）按空白或數字鍵：清掉字碼，而不是停在那裡
    "sync_remote": "",        # 學習資料同步用的 git 版本庫（ssh 網址）；空的＝不同步
    "sync_name": "",          # 這台電腦在同步資料夾裡的檔名（sync.py 第一次執行時填入）
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


def update(path, **changes):
    """重讀再改：別的程式（sync.py、其他輸入框）可能剛改過檔案，不能拿舊的整份蓋回去。"""
    s = load(path)
    s.update(changes)
    save(path, s)
    return s
