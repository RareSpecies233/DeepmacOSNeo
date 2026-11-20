#!/bin/bash
# 构建 → 启动 → 截取 DeepGlass 窗口 → 输出到 .screenshots/mac-<name>.png
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1
NAME="${1:-main}"
mkdir -p .screenshots
xcodebuild -project DeepGlass.xcodeproj -scheme DeepGlass-macOS -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath build/dd-mac build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
APP="$(find build/dd-mac -name 'DeepGlass.app' -path '*Debug*' -maxdepth 6 | head -1)"
[ -z "$APP" ] && { echo "app not found"; exit 1; }
pkill -x DeepGlass 2>/dev/null
sleep 1
open "$APP"
sleep 4
WID="$(swift scripts/window-id.swift DeepGlass 2>/dev/null)"
if [ -n "$WID" ]; then
  screencapture -x -o -l"$WID" ".screenshots/mac-$NAME.png"
  echo "captured window $WID -> .screenshots/mac-$NAME.png"
else
  screencapture -x ".screenshots/mac-$NAME.png"
  echo "captured full screen -> .screenshots/mac-$NAME.png"
fi
