#!/usr/bin/env bash
# 在 Mac 上編譯並安裝到 ~/Library/Input Methods/CangjieLearn.app。
# 用法：mac/build.sh [--no-install]
# 需要：Xcode command line tools；data/model.db（在 Linux 跑 scripts/build_data.py 產生後一起複製過來）。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/mac/build"
APP="$OUT/CangjieLearn.app"
VERSION="$(date +%Y.%m.%d)"
rm -rf "$OUT"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -swift-version 5 -module-name CangjieLearn \
    "$ROOT"/mac/Core/Model.swift "$ROOT"/mac/Core/Composer.swift "$ROOT"/mac/App/*.swift \
    -framework Cocoa -framework InputMethodKit -o "$APP/Contents/MacOS/CangjieLearn"
sed "s/VERSION/$VERSION/g" "$ROOT/mac/App/Info.plist" > "$APP/Contents/Info.plist"
cp "$ROOT/data/model.db" "$APP/Contents/Resources/"
swift "$ROOT/mac/tools/make_icon.swift" "$APP/Contents/Resources/icon.tiff"
swiftc -O "$ROOT/mac/tools/tis.swift" -framework Carbon -o "$OUT/tis"
codesign --force --sign - "$APP"
echo "built $APP"

[ "${1:-}" = "--no-install" ] && exit 0
DEST="$HOME/Library/Input Methods/CangjieLearn.app"
pkill -x CangjieLearn || true        # 舊版程序結束後，系統下次需要時會自動啟動新版
mkdir -p "$HOME/Library/Input Methods"
rm -rf "$DEST"; cp -R "$APP" "$DEST"
"$OUT/tis" register "$DEST"
"$OUT/tis" status
