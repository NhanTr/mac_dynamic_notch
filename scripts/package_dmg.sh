#!/usr/bin/env bash
# Builds a Universal (arm64 + x86_64, macOS 14+) release DynamicNotch.app
# and packages it into a distributable .dmg with custom icons and a Gatekeeper helper.
#
# Usage: scripts/package_dmg.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

export CLANG_MODULE_CACHE_PATH="$ROOT/.build/module-cache"

# Generate Support/AppIcon.icns if not present yet.
if [ ! -f "$ROOT/Support/AppIcon.icns" ]; then
    swift "$ROOT/scripts/generate_icon.swift" "$ROOT/build/AppIcon.iconset" "$ROOT/build/AppIcon-1024.png"
    iconutil -c icns "$ROOT/build/AppIcon.iconset" -o "$ROOT/Support/AppIcon.icns"
fi

"$ROOT/scripts/bundle.sh" release

STAGE="$ROOT/build/dmg-stage"
DMG="$ROOT/build/DynamicNotch-1.0.0.dmg"

rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$ROOT/build/DynamicNotch.app" "$STAGE/DynamicNotch.app"
ln -s /Applications "$STAGE/Applications"

# Helper script for Macs where Gatekeeper quarantines ad-hoc signed apps.
cat > "$STAGE/Install & Open (Fix Gatekeeper).command" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
echo "Installing DynamicNotch to /Applications..."
rm -rf /Applications/DynamicNotch.app
cp -R "$DIR/DynamicNotch.app" /Applications/DynamicNotch.app
xattr -cr /Applications/DynamicNotch.app
codesign --force --deep --sign - /Applications/DynamicNotch.app 2>/dev/null || true
echo "Opening DynamicNotch..."
open /Applications/DynamicNotch.app
echo "Done! Look for the laptop icon in the top-right menu bar."
EOF
chmod +x "$STAGE/Install & Open (Fix Gatekeeper).command"

# Set custom volume icon for the mounted DMG disk on Desktop / Finder sidebar.
if [ -f "$ROOT/Support/AppIcon.icns" ]; then
    cp "$ROOT/Support/AppIcon.icns" "$STAGE/.VolumeIcon.icns"
    /usr/bin/SetFile -c icnC "$STAGE/.VolumeIcon.icns" 2>/dev/null || true
    /usr/bin/SetFile -a C "$STAGE" 2>/dev/null || true
fi

hdiutil create \
    -volname "DynamicNotch" \
    -srcfolder "$STAGE" \
    -ov \
    -format UDZO \
    "$DMG"

# Also attach the custom icon to the .dmg file itself in Finder.
if [ -f "$ROOT/Support/AppIcon.icns" ]; then
    swift -e '
    import AppKit
    let args = CommandLine.arguments
    if let icon = NSImage(contentsOfFile: args[1]) {
        NSWorkspace.shared.setIcon(icon, forFile: args[2], options: [])
    }
    ' "$ROOT/Support/AppIcon.icns" "$DMG"
fi

rm -rf "$STAGE"
echo "Packaged $DMG (Universal arm64+x86_64, macOS 14.0+, with custom icons)"
