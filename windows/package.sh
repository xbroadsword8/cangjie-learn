#!/usr/bin/env bash
# 產生 Windows 安裝程式 windows/dist/cangjie-learn-pime-setup-<日期>.exe（含 PIME 1.3.0 官方安裝檔）。
# makensis 不需 root：apt-get download nsis nsis-common 後 dpkg -x 到 $NSIS_ROOT。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NSIS_ROOT="${NSIS_ROOT:-$HOME/.local/opt/nsis}"
if [ ! -x "$NSIS_ROOT/usr/bin/makensis" ]; then
    tmp=$(mktemp -d); (cd "$tmp" && apt-get download nsis nsis-common >/dev/null)
    mkdir -p "$NSIS_ROOT"; for f in "$tmp"/*.deb; do dpkg -x "$f" "$NSIS_ROOT"; done; rm -rf "$tmp"
fi
SETUP="$ROOT/windows/vendor/PIME-1.3.0-stable-setup.exe"
PIME_SHA=6b2e288b95085a52f378f023fb17128f5b1389a3cdae078c7e4d47c1b4e9dc35
[ -f "$SETUP" ] || curl -fL -o "$SETUP" https://github.com/EasyIME/PIME/releases/download/v1.3.0-stable/PIME-1.3.0-stable-setup.exe
echo "$PIME_SHA  $SETUP" | sha256sum -c --quiet

VERSION=$(date +%Y.%m.%d)
BUILD=$("$ROOT/windows/build.sh")
STAGE="$ROOT/windows/dist/stage"
rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -r "$BUILD" "$STAGE/cjlearn"
cp "$ROOT/windows/smoke_pime.py" "$SETUP" "$STAGE/"
# Windows PowerShell 5.1 要 UTF-8 BOM 才讀得懂中文；行尾改 CRLF
printf '\xef\xbb\xbf' > "$STAGE/setup.ps1"; sed 's/$/\r/' "$ROOT/windows/installer/setup.ps1" >> "$STAGE/setup.ps1"
OUT="$ROOT/windows/dist/cangjie-learn-pime-setup-$(date +%Y%m%d).exe"
NSISDIR="$NSIS_ROOT/usr/share/nsis" "$NSIS_ROOT/usr/bin/makensis" -V2 -INPUTCHARSET UTF8 \
    -DVERSION="$VERSION" -DSTAGE="$STAGE" -DOUTFILE="$OUT" "$ROOT/windows/installer/cangjie-learn.nsi"
rm -rf "$STAGE"
echo "$OUT"
