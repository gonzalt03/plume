#!/bin/bash
# Compile Plume.app, l'installe dans ~/Applications et le lance.
set -euo pipefail
cd "$(dirname "$0")"

APP="Plume"
BUNDLE="build/$APP.app"
DEST="$HOME/Applications/$APP.app"

rm -rf build
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"

# Binaire universel : Apple Silicon + Intel.
for ARCH in arm64 x86_64; do
  swiftc -O -swift-version 5 -target "$ARCH-apple-macos13.0" Sources/*.swift -o "build/$APP-$ARCH"
done
lipo -create "build/$APP-arm64" "build/$APP-x86_64" -output "$BUNDLE/Contents/MacOS/$APP"
rm -f "build/$APP-arm64" "build/$APP-x86_64"
cp Info.plist "$BUNDLE/Contents/Info.plist"

# Icônes (régénérées par tools/make-icon.swift).
[ -d Resources/AppIcon.iconset ] || swift tools/make-icon.swift Resources
iconutil -c icns Resources/AppIcon.iconset -o "$BUNDLE/Contents/Resources/AppIcon.icns"
cp Resources/MenuBarIcon.png Resources/MenuBarIcon@2x.png "$BUNDLE/Contents/Resources/"

# Signature : identité « Plume » si créée (permission d'accessibilité conservée
# entre deux compilations), sinon signature ad hoc.
IDENTITY="-"
if security find-identity -p codesigning 2>/dev/null | grep -q '"Plume"'; then
  IDENTITY="Plume"
fi
codesign --force --sign "$IDENTITY" "$BUNDLE"

# --no-install : compile seulement (utilisé par scripts/make-dmg.sh).
[ "${1:-}" = "--no-install" ] && { echo "Compilé : $BUNDLE"; exit 0; }

pkill -x "$APP" 2>/dev/null || true
mkdir -p "$HOME/Applications"
rm -rf "$DEST"
cp -R "$BUNDLE" "$DEST"
open "$DEST"
echo "Installé : $DEST (signature : $IDENTITY)"
