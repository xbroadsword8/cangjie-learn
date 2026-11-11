#!/usr/bin/env bash
# 產生倉頡學習版（TSF 原生版）安裝程式 windows/dist/cangjie-learn-setup-<日期>.exe（含 MinGit，不含 PIME）。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NSIS_ROOT="${NSIS_ROOT:-$HOME/.local/opt/nsis}"
if [ ! -x "$NSIS_ROOT/usr/bin/makensis" ]; then
    tmp=$(mktemp -d); (cd "$tmp" && apt-get download nsis nsis-common >/dev/null)
    mkdir -p "$NSIS_ROOT"; for f in "$tmp"/*.deb; do dpkg -x "$f" "$NSIS_ROOT"; done; rm -rf "$tmp"
fi
MINGIT="$ROOT/windows/vendor/MinGit-2.56.0.4-64-bit.zip"
MINGIT_SHA=e3bf78351fe777fba47ddee5950082f8a98bb0f02604fdc7ba3ee2cb68ffa877
mkdir -p "$ROOT/windows/vendor"
[ -f "$MINGIT" ] || curl -fL -o "$MINGIT" https://github.com/git-for-windows/git/releases/download/v2.56.0.windows.4/MinGit-2.56.0.4-64-bit.zip
echo "$MINGIT_SHA  $MINGIT" | sha256sum -c --quiet
[ -f "$ROOT/data/model.db" ] || { echo "缺 data/model.db（先跑 ./install.sh 或 scripts/build_data.py）"; exit 1; }

: "${CARGO_TARGET_DIR:=$ROOT/windows/build/tsf-target}"; export CARGO_TARGET_DIR
( cd "$ROOT/windows/tsf"
  for t in x86_64-pc-windows-gnu i686-pc-windows-gnu; do cargo build -q -p chewing_tip --release --target $t; done
  cargo build -q -p tsfreg --release --target x86_64-pc-windows-gnu
  cargo build -q -p cangjie_core --release --target x86_64-pc-windows-gnu --bin cjlearn-sync )
R64="$CARGO_TARGET_DIR/x86_64-pc-windows-gnu/release"; R32="$CARGO_TARGET_DIR/i686-pc-windows-gnu/release"

STAGE="$ROOT/windows/dist/stage-tsf"
rm -rf "$STAGE"; mkdir -p "$STAGE/x64" "$STAGE/x86"
cp "$R64/cjlearn_tip.dll" "$STAGE/x64/"; cp "$R32/cjlearn_tip.dll" "$STAGE/x86/"
cp "$R64/tsfreg.exe" "$R64/cjlearn-sync.exe" "$ROOT/data/model.db" "$MINGIT" "$STAGE/"
cp "$ROOT/windows/pime/cjlearn/icons/chi_half_capsoff.ico" "$STAGE/cjlearn.ico"
# Windows PowerShell 5.1 要 UTF-8 BOM 才讀得懂中文；行尾改 CRLF
printf '\xef\xbb\xbf' > "$STAGE/setup-tsf.ps1"; sed 's/$/\r/' "$ROOT/windows/installer/setup-tsf.ps1" >> "$STAGE/setup-tsf.ps1"
OUT="$ROOT/windows/dist/cangjie-learn-setup-$(date +%Y%m%d).exe"
NSISDIR="$NSIS_ROOT/usr/share/nsis" "$NSIS_ROOT/usr/bin/makensis" -V2 -INPUTCHARSET UTF8 \
    -DVERSION="$(date +%Y.%m.%d)" -DSTAGE="$STAGE" -DOUTFILE="$OUT" "$ROOT/windows/installer/cangjie-learn-tsf.nsi"
rm -rf "$STAGE"
echo "$OUT"
