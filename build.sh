#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$ROOT/.build"
APP="$ROOT/dist/AI Monitor.app"
CACHE="$BUILD_DIR/cache"

mkdir -p "$CACHE" "$ROOT/dist"

echo "==> 编译 Swift 源码"
swiftc -O \
  -module-cache-path "$CACHE" \
  $(find "$ROOT/Sources/AIMonitor" -name '*.swift') \
  -o "$BUILD_DIR/AIMonitor" \
  -framework AppKit \
  -framework SwiftUI \
  -framework UserNotifications

echo "==> 组装 app bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD_DIR/AIMonitor" "$APP/Contents/MacOS/AIMonitor"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
  cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

echo "==> 签名（ad-hoc）"
codesign --force --sign - "$APP" >/dev/null 2>&1

echo "==> 完成: $APP"
