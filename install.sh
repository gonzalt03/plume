#!/bin/bash
# Installe (ou met à jour) Plume depuis la dernière release GitHub.
# Usage : curl -fsSL https://raw.githubusercontent.com/gonzalt03/plume/main/install.sh | bash
set -euo pipefail

REPO="gonzalt03/plume"
if [ -n "${PLUME_DEST:-}" ]; then
  DEST="$PLUME_DEST"
elif [ -w /Applications ]; then
  DEST="/Applications"
else
  DEST="$HOME/Applications"
fi
mkdir -p "$DEST"

echo "Recherche de la dernière version de Plume…"
URL=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
  | grep -o '"browser_download_url": *"[^"]*\.dmg"' | head -1 | sed -E 's/.*"(https[^"]+)"$/\1/')
[ -n "$URL" ] || { echo "Aucun DMG trouvé dans la dernière release."; exit 1; }

TMP=$(mktemp -d)
MNT="$TMP/mnt"
trap 'hdiutil detach "$MNT" -quiet 2>/dev/null || true; rm -rf "$TMP"' EXIT
mkdir -p "$MNT"

echo "Téléchargement de $URL"
curl -fsSL "$URL" -o "$TMP/Plume.dmg"
hdiutil attach "$TMP/Plume.dmg" -nobrowse -readonly -noautoopen -mountpoint "$MNT" -quiet

pkill -x Plume 2>/dev/null || true
rm -rf "$DEST/Plume.app"
ditto "$MNT/Plume.app" "$DEST/Plume.app"
xattr -dr com.apple.quarantine "$DEST/Plume.app" 2>/dev/null || true

echo "Plume installée dans $DEST/Plume.app"
if [ -z "${PLUME_NO_OPEN:-}" ]; then
  open "$DEST/Plume.app"
  echo "Autorise Plume dans Réglages Système > Confidentialité et sécurité > Accessibilité."
fi
