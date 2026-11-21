#!/bin/bash
# 用法: scripts/build.sh <easy-name> [mac|ios]
# 每个调用者用自己的 derivedDataPath，避免构建产物互相覆盖
set -uo pipefail
export PATH="/opt/homebrew/bin:$PATH"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NAME="${1:-anon}"
KIND="${2:-mac}"
cd "$ROOT" || exit 1
if [ "$KIND" = "ios" ]; then
  xcodebuild -project DeepGlass.xcodeproj -scheme DeepGlass-iOS -configuration Debug \
    -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
    -derivedDataPath "build/dd-$NAME" build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)" | head -40
else
  xcodebuild -project DeepGlass.xcodeproj -scheme DeepGlass-macOS -configuration Debug \
    -destination 'platform=macOS' \
    -derivedDataPath "build/dd-$NAME" build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)" | head -40
fi
