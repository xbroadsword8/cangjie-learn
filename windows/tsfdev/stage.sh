#!/usr/bin/env bash
# 編 x64／x86 DLL 與 tsfreg，組成 devinstall.ps1 要的資料夾。用法：windows/tsfdev/stage.sh <輸出資料夾>
#   選用：DEPLOY=<ssh 主機> 會再 scp 到對方 ~/cjtsf 並以系統管理員跑 devinstall.ps1
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
OUT=${1:?輸出資料夾}
: "${CARGO_TARGET_DIR:=$ROOT/windows/build/tsf-target}"
export CARGO_TARGET_DIR
cd "$ROOT/windows/tsf"
for t in x86_64-pc-windows-gnu i686-pc-windows-gnu; do
  cargo build -q -p chewing_tip --release --target $t
done
cargo build -q -p tsfreg --release --target x86_64-pc-windows-gnu
rm -rf "$OUT"; mkdir -p "$OUT/x64" "$OUT/x86"
cp "$CARGO_TARGET_DIR/x86_64-pc-windows-gnu/release/cjlearn_tip.dll" "$OUT/x64/"
cp "$CARGO_TARGET_DIR/i686-pc-windows-gnu/release/cjlearn_tip.dll" "$OUT/x86/"
cp "$CARGO_TARGET_DIR/x86_64-pc-windows-gnu/release/tsfreg.exe" "$OUT/"
cp "$ROOT/windows/tsf/tip/rc/cjlearn_cj.ico" "$OUT/cjlearn.ico"
[ -f "$ROOT/data/model.db" ] || { echo "缺 data/model.db（先跑 ./install.sh 或 scripts/build_data.py）"; exit 1; }
cp "$ROOT/data/model.db" "$OUT/"
# Windows PowerShell 5 要 BOM 才讀得懂 UTF-8 中文
printf '\xef\xbb\xbf' | cat - "$ROOT/windows/tsfdev/devinstall.ps1" > "$OUT/devinstall.ps1"
ls -la "$OUT" "$OUT/x64" "$OUT/x86"
if [ -n "${DEPLOY:-}" ]; then
  ssh "$DEPLOY" 'powershell -NoProfile -Command "Remove-Item -Recurse -Force $env:USERPROFILE\cjtsf -EA SilentlyContinue; exit 0"'
  scp -rq "$OUT" "$DEPLOY:cjtsf"
  ssh "$DEPLOY" 'powershell -NoProfile -ExecutionPolicy Bypass -Command "& $env:USERPROFILE\cjtsf\devinstall.ps1 -Src $env:USERPROFILE\cjtsf ${DEVARGS:-}"'
fi
