#!/usr/bin/env bash
# 安裝「倉頡學習版」IBus 引擎（不需 root）。
# 做的事：1) 建 data/model.db  2) 放啟動殼與 component XML 到 ~/.local
#         3) 讓 GNOME 的 ibus-daemon 透過 IBUS_COMPONENT_PATH 找到它  4) 重啟 ibus
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
LIBEXEC="$HOME/.local/libexec"
COMPDIR="$HOME/.local/share/cangjie-learn/component"
UNIT=org.freedesktop.IBus.session.GNOME.service
DROPIN="$HOME/.config/systemd/user/$UNIT.d"

[ -f "$ROOT/data/model.db" ] || python3 "$ROOT/scripts/build_data.py"

mkdir -p "$LIBEXEC" "$COMPDIR" "$DROPIN"
cat > "$LIBEXEC/ibus-engine-cangjie-learn" <<SH
#!/bin/sh
cd "$ROOT" && exec /usr/bin/python3 -m cjlearn.main "\$@"
SH
chmod +x "$LIBEXEC/ibus-engine-cangjie-learn"

cat > "$COMPDIR/cangjie-learn.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<component>
  <name>org.freedesktop.IBus.CangjieLearn</name>
  <description>倉頡學習版</description>
  <exec>$LIBEXEC/ibus-engine-cangjie-learn --ibus</exec>
  <version>0.1</version>
  <author>xbroadsword8</author>
  <license>LGPL-2.1-or-later</license>
  <textdomain>cangjie-learn</textdomain>
  <engines>
    <engine>
      <name>cangjie-learn</name>
      <language>zh_TW</language>
      <license>LGPL-2.1-or-later</license>
      <author>xbroadsword8</author>
      <icon>/usr/share/ibus-table/icons/cangjie3.svg</icon>
      <layout>us</layout>
      <longname>倉頡學習版</longname>
      <description>倉頡三代＋上下文選字＋學習；標點預設半形，Ctrl＋標點出全形</description>
      <rank>0</rank>
      <symbol>倉</symbol>
    </engine>
  </engines>
</component>
XML

cat > "$DROPIN/cangjie-learn.conf" <<CONF
[Service]
Environment=IBUS_COMPONENT_PATH=/usr/share/ibus/component:$COMPDIR
CONF
systemctl --user daemon-reload
# IBUS_COMPONENT_PATH 會取代（不是附加）系統路徑，所以上面一定要含 /usr/share/ibus/component
IBUS_COMPONENT_PATH=/usr/share/ibus/component:$COMPDIR ibus write-cache 2>/dev/null || true
systemctl --user restart "$UNIT"
sleep 2
ibus list-engine | grep -q cangjie-learn && echo "已註冊：cangjie-learn" || { echo "ibus 沒看到 cangjie-learn"; exit 1; }
