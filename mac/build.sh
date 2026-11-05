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
mkdir -p "$APP/Contents/Resources/sync"     # 學習資料同步程式（launchd 用系統的 python3 跑）
cp "$ROOT/cjlearn/sync.py" "$ROOT/cjlearn/settings.py" "$APP/Contents/Resources/sync/"
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

# 學習資料同步：這台專用的金鑰＋每 15 分鐘的 launchd 排程（settings.json 沒設 sync_remote 時什麼都不做）
DATA="$HOME/Library/Application Support/CangjieLearn"
mkdir -p "$DATA"
[ -f "$DATA/sync_key" ] || ssh-keygen -q -t ed25519 -N "" -C "cjlearn-$(hostname -s | tr A-Z a-z)" -f "$DATA/sync_key"
echo "同步金鑰（要加到伺服器才能同步）：$(cat "$DATA/sync_key.pub")"
LABEL=com.xmac.inputmethod.CangjieLearn.sync
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key><string>$LABEL</string>
	<key>ProgramArguments</key>
	<array>
		<string>/usr/bin/python3</string>
		<string>$DEST/Contents/Resources/sync/sync.py</string>
		<string>$DATA</string>
	</array>
	<key>StartInterval</key><integer>900</integer>
	<key>RunAtLoad</key><true/>
	<key>StandardErrorPath</key><string>$DATA/sync.err.log</string>
</dict>
</plist>
PL
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "已設定排程 $LABEL（每 15 分鐘）"
