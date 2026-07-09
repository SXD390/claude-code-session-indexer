#!/bin/zsh
# Builds ClaudeSessions in release mode and assembles "Claude Code Session Indexer.app" in dist/.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="Claude Code Session Indexer"
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
    <string>Claude Code Session Indexer</string>
    <key>CFBundleDisplayName</key>
    <string>Claude Code Session Indexer</string>
    <key>CFBundleIdentifier</key>
    <string>com.sxd390.claude-session-indexer</string>
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

# Signing. Defaults to ad-hoc ("-") for local use. For a distributable build, export a
# Developer ID cert name so the app is signed with Hardened Runtime + a secure timestamp — the
# prerequisites for notarization (see docs/security/macos-audit.md):
#   CODESIGN_ID="Developer ID Application: Your Name (TEAMID)" scripts/build_app.sh
# then notarize the bundle with `xcrun notarytool submit` and `xcrun stapler staple`.
CODESIGN_ID="${CODESIGN_ID:--}"
if [ "$CODESIGN_ID" = "-" ]; then
    echo "→ codesign (ad-hoc — local use only, not for distribution)"
    codesign --force -s - "$APP"
else
    echo "→ codesign (Developer ID + Hardened Runtime): $CODESIGN_ID"
    codesign --force --options runtime --timestamp -s "$CODESIGN_ID" "$APP"
fi

echo "✓ Built: $APP"
