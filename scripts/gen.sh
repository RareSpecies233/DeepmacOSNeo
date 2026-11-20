#!/bin/bash
# 带锁的工程生成：多个代理可并发调用而不会同时写 .xcodeproj
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOCK="/tmp/deepglass-xcodegen.lock"
for i in $(seq 1 60); do
  if mkdir "$LOCK" 2>/dev/null; then
    trap 'rmdir "$LOCK" 2>/dev/null || true' EXIT
    cd "$ROOT" && xcodegen generate >/dev/null
    echo "project generated"
    exit 0
  fi
  sleep 1
done
echo "could not acquire xcodegen lock" >&2
exit 1
