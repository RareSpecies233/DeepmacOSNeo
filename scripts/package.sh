#!/bin/bash
# 生成可分发的 macOS 应用：dist/DeepGlass.app 与 dist/DeepGlass-<version>.zip
# 用法: ./scripts/package.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="$(sed -n 's/.*MARKETING_VERSION: "\([0-9][0-9.]*"\)".*/\1/p' project.yml | tr -d '"' | head -1)"
VERSION="${VERSION:-0.1.0}"

echo "▸ 生成工程"
./scripts/gen.sh

echo "▸ Release 构建（macOS）"
xcodebuild -project DeepGlass.xcodeproj -scheme DeepGlass-macOS \
  -configuration Release -destination 'platform=macOS' \
  -derivedDataPath build/dd-release build 2>&1 \
  | grep -E "error:|BUILD (SUCCEEDED|FAILED)" || true

APP="$(find build/dd-release/Build/Products/Release -maxdepth 2 -name 'DeepGlass.app' | head -1)"
[ -z "$APP" ] && { echo "未找到产物"; exit 1; }

echo "▸ 组装 dist/"
rm -rf dist && mkdir -p dist
ditto "$APP" "dist/DeepGlass.app"

# ad-hoc 签名：本机与局域网分发可运行；对外分发仍需 Developer ID + 公证
codesign --force --deep --sign - "dist/DeepGlass.app" >/dev/null 2>&1 || true
codesign --verify --deep --strict "dist/DeepGlass.app" && echo "✓ 签名校验通过（ad-hoc）"

ditto -c -k --keepParent "dist/DeepGlass.app" "dist/DeepGlass-$VERSION.zip"

echo
echo "完成："
echo "  App : $ROOT/dist/DeepGlass.app"
echo "  Zip : $ROOT/dist/DeepGlass-$VERSION.zip"
echo "  大小: $(du -sh dist/DeepGlass.app | cut -f1)"
