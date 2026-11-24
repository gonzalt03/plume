#!/bin/bash
# Publie une nouvelle version : scripts/release.sh 1.2 notes.md
# Met à jour Info.plist, contrôle les données sensibles, commit, tag, push,
# construit le DMG et crée la release GitHub (que Plume détecte pour se mettre à jour).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?Usage : scripts/release.sh <version> <fichier-notes.md>}"
NOTES="${2:?Fichier de notes de version requis}"
[ -z "$(git status --porcelain)" ] || { echo "Arbre de travail non propre : committer d'abord."; exit 1; }

scripts/check-public.sh all

BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" Info.plist)
/usr/libexec/PlistBuddy -c "Set CFBundleShortVersionString $VERSION" Info.plist
/usr/libexec/PlistBuddy -c "Set CFBundleVersion $((BUILD + 1))" Info.plist
git commit -qam "Version $VERSION"
git tag -a "v$VERSION" -m "Plume $VERSION"

scripts/make-dmg.sh
git push -q origin HEAD "v$VERSION"
gh release create "v$VERSION" "build/Plume-$VERSION.dmg" --title "Plume $VERSION" --notes-file "$NOTES"
