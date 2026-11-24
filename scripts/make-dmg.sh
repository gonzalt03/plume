#!/bin/bash
# Construit build/Plume-<version>.dmg : fenêtre avec fond, icône Plume et raccourci Applications.
# Prérequis : brew install create-dmg
set -euo pipefail
cd "$(dirname "$0")/.."

./build.sh --no-install
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Info.plist)
DMG="build/Plume-$VERSION.dmg"
STAGE=$(mktemp -d)
cp -R build/Plume.app "$STAGE/"
rm -f "$DMG"

create-dmg \
  --volname "Plume" \
  --volicon build/Plume.app/Contents/Resources/AppIcon.icns \
  --background Resources/dmg-background.tiff \
  --window-pos 200 160 \
  --window-size 660 400 \
  --icon-size 120 \
  --text-size 13 \
  --icon "Plume.app" 170 200 \
  --hide-extension "Plume.app" \
  --app-drop-link 490 200 \
  --no-internet-enable \
  "$DMG" "$STAGE"

rm -rf "$STAGE"
echo "DMG : $DMG"
