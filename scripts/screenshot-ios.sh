#!/bin/bash
# 构建 → 装到模拟器 → 启动 → 截图
set -uo pipefail
export PATH="/opt/homebrew/bin:$PATH"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1
DEVICE="${1:-iPhone 18 Pro}"
NAME="${2:-iphone}"
mkdir -p .screenshots
xcrun simctl boot "$DEVICE" 2>/dev/null
open -a Simulator
xcrun simctl bootstatus "$DEVICE" -b >/dev/null 2>&1
xcodebuild -project DeepGlass.xcodeproj -scheme DeepGlass-iOS -configuration Debug \
  -destination "platform=iOS Simulator,name=$DEVICE" -derivedDataPath build/dd-ios build 2>&1 \
  | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
APP="$(find build/dd-ios -name 'DeepGlass.app' -path '*Debug-iphonesimulator*' -maxdepth 6 | head -1)"
[ -z "$APP" ] && { echo "app not found"; exit 1; }
xcrun simctl terminate "$DEVICE" com.deepglass.app 2>/dev/null
xcrun simctl install "$DEVICE" "$APP"
xcrun simctl launch "$DEVICE" com.deepglass.app >/dev/null
sleep 3
xcrun simctl io "$DEVICE" screenshot ".screenshots/$NAME.png" 2>/dev/null
echo "captured -> .screenshots/$NAME.png"
