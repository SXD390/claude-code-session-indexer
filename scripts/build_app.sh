#!/bin/zsh
# Builds ClaudeSessions in release mode and assembles "Reprise.app" in dist/.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="Reprise"
APP="$ROOT/dist/$APP_NAME.app"

echo "→ swift build -c release"
swift build -c release

echo "→ assembling bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$ROOT/.build/release/ClaudeSessions" "$APP/Contents/MacOS/ClaudeSessions"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Reprise</string>
    <key>CFBundleDisplayName</key>
    <string>Reprise</string>
    <key>CFBundleIdentifier</key>
    <string>com.sxd390.reprise</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleExecutable</key>
    <string>ClaudeSessions</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.developer-tools</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Built with Claude Code</string>
</dict>
</plist>
PLIST

if [ ! -f "$ROOT/dist/AppIcon.icns" ]; then
    echo "→ rendering icon"
    ICONSET="$ROOT/dist/AppIcon.iconset"
    rm -rf "$ICONSET"
    swift "$ROOT/scripts/make_icon.swift" "$ICONSET"
    iconutil -c icns "$ICONSET" -o "$ROOT/dist/AppIcon.icns"
    rm -rf "$ICONSET"
fi
cp "$ROOT/dist/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

echo "→ codesign (ad-hoc)"
codesign --force -s - "$APP"

echo "✓ Built: $APP"
