#!/usr/bin/env bash
# Builds DynamicNotch and wraps the executable in a proper .app bundle.
#
# Usage: scripts/bundle.sh [debug|release]   (default: release)
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/DynamicNotch.app"

cd "$ROOT"
export CLANG_MODULE_CACHE_PATH="$ROOT/.build/module-cache"
SWIFT_FLAGS=(-c "$CONFIG" --disable-sandbox --cache-path "$ROOT/.build/swiftpm-cache")

# Release builds produce a Universal Binary (Apple Silicon arm64 + Intel x86_64)
# targeting macOS 14.0+ so the .app runs across different Macs.
if [ "$CONFIG" = "release" ]; then
    SWIFT_FLAGS+=(--arch arm64 --arch x86_64)
fi

swift build "${SWIFT_FLAGS[@]}"
BIN_DIR="$(swift build "${SWIFT_FLAGS[@]}" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/DynamicNotch" "$APP/Contents/MacOS/DynamicNotch"
cp "$ROOT/Support/Info.plist" "$APP/Contents/Info.plist"
if [ -f "$ROOT/Support/AppIcon.icns" ]; then
    cp "$ROOT/Support/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

# Strip any extended/quarantine attributes before signing.
xattr -cr "$APP" 2>/dev/null || true

# Ad-hoc signature for local/direct distribution.
codesign --force --deep --sign - --timestamp=none "$APP"

echo "Built $APP"
