#!/bin/bash
# Régénère Resources/AppIcon.icns depuis le dessin du chat (CatIcon.swift).
set -euo pipefail
cd "$(dirname "$0")/.."

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
# Le code du script doit s'appeler main.swift pour être compilé avec les fichiers de l'app.
cp scripts/make-icon.swift "$TMP/main.swift"
swiftc -O -o "$TMP/make-icon" "$TMP/main.swift" Sources/BlackCat/CatIcon.swift Sources/BlackCat/Theme.swift
"$TMP/make-icon" "$TMP/AppIcon.iconset"
iconutil -c icns "$TMP/AppIcon.iconset" -o Resources/AppIcon.icns
cp "$TMP/AppIcon.iconset/icon_512x512@2x.png" docs/icone-1024.png

echo "OK : Resources/AppIcon.icns"
