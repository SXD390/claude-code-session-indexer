#!/bin/zsh
# Builds an ad-hoc-signed .dmg of Claude Code Session Indexer.
#
# ⚠️  READ THIS FIRST — this DMG is NOT notarized by Apple.
#   Because it is only ad-hoc signed (no paid Apple Developer ID, no
#   notarization), macOS Gatekeeper will refuse to open it on first launch
#   with "cannot be opened because it is from an unidentified developer."
#   Users must either right-click the app → Open (and confirm once), or run:
#       xattr -dr com.apple.quarantine "/Applications/Claude Code Session Indexer.app"
#   For a friction-free double-click experience you need Developer ID signing
#   + notarization (see docs/security/macos-audit.md → Code signing).
#
# Prefer building from source (./scripts/build_app.sh) — that binary is
# locally compiled and carries no quarantine flag.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="Claude Code Session Indexer"
APP="$ROOT/dist/$APP_NAME.app"
DMG="$ROOT/dist/$APP_NAME.dmg"
STAGE="$ROOT/dist/dmg-stage"

echo "→ building app bundle"
"$ROOT/scripts/build_app.sh"

echo "→ staging"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

echo "→ creating compressed dmg"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

echo "→ ad-hoc signing the dmg"
codesign --force -s - "$DMG" 2>/dev/null || true

echo "✓ Built (ad-hoc, NOT notarized): $DMG"
echo "  Users will see a Gatekeeper warning — see the header of this script."
