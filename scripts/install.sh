#!/usr/bin/env bash
# One-step build, install to /Applications, and launch for users cloning from GitHub.
#
# Usage: ./scripts/install.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

export CLANG_MODULE_CACHE_PATH="$ROOT/.build/module-cache"

if [ ! -f "$ROOT/Support/AppIcon.icns" ]; then
    echo "==> Generating AppIcon.icns..."
    swift "$ROOT/scripts/generate_icon.swift" "$ROOT/build/AppIcon.iconset" "$ROOT/build/AppIcon-1024.png"
    iconutil -c icns "$ROOT/build/AppIcon.iconset" -o "$ROOT/Support/AppIcon.icns"
fi

echo "==> Building DynamicNotch (Release)..."
SWIFT_FLAGS=(-c release --disable-sandbox --cache-path "$ROOT/.build/swiftpm-cache")
swift build "${SWIFT_FLAGS[@]}"
BIN_DIR="$(swift build "${SWIFT_FLAGS[@]}" --show-bin-path)"

APP="$ROOT/build/DynamicNotch.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/DynamicNotch" "$APP/Contents/MacOS/DynamicNotch"
cp "$ROOT/Support/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Support/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

xattr -cr "$APP" 2>/dev/null || true
codesign --force --deep --sign - --timestamp=none "$APP"

echo "==> Installing to /Applications/DynamicNotch.app..."
pkill -x DynamicNotch 2>/dev/null || true
rm -rf /Applications/DynamicNotch.app
cp -R "$APP" /Applications/DynamicNotch.app

echo "==> Launching DynamicNotch..."
open /Applications/DynamicNotch.app
echo "Done! DynamicNotch is running in your menu bar."
