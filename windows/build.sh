#!/usr/bin/env bash
# 組出 PIME 輸入法目錄 windows/build/cjlearn/：外殼（windows/pime/cjlearn）＋核心（cjlearn/model.py、composer.py、settings.py）＋ data/model.db
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/windows/build/cjlearn"
[ -f "$ROOT/data/model.db" ] || python3 "$ROOT/scripts/build_data.py"
rm -rf "$OUT"
mkdir -p "$OUT/core" "$OUT/data"
cp "$ROOT"/windows/pime/cjlearn/{__init__.py,cjlearn_ime.py,keymap.py,ime.json,icon.ico} "$OUT/"
cp "$ROOT"/cjlearn/{model.py,composer.py,settings.py} "$OUT/core/"
touch "$OUT/core/__init__.py"
cp "$ROOT/data/model.db" "$OUT/data/"
echo "$OUT"
