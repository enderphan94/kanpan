#!/bin/bash
# Packages dist/Kanpan.app into a distributable .dmg with an Applications
# drop-link. Run ./build.sh first.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Kanpan"
VERSION="1.0.0"
APP="dist/${APP_NAME}.app"
DMG="dist/${APP_NAME}-${VERSION}.dmg"

if [ ! -d "$APP" ]; then
  echo "✗ $APP not found — run ./build.sh first." >&2
  exit 1
fi

STAGE="build/dmg"
rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

# A short note users see in the mounted volume.
cat > "$STAGE/READ ME FIRST.txt" <<'TXT'
Installing Kanpan
=================
1. Drag "Kanpan" onto the Applications folder.
2. First launch: right-click Kanpan → Open → Open (the app is unsigned,
   so Gatekeeper needs this one-time confirmation).
3. On first run, choose where to keep your Vault (a plain folder of .md files).

Your tasks are stored as Markdown you fully own — back them up, sync with
iCloud, or edit them in Obsidian.
TXT

rm -f "$DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" \
  -ov -format UDZO "$DMG" >/dev/null

echo "✓ Created $DMG"
du -sh "$DMG" | awk '{print "  size: "$1}'
