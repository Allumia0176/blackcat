#!/bin/bash
# Fabrique build/BlackCat.app
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP="build/BlackCat.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/BlackCat "$APP/Contents/MacOS/BlackCat"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"  # logo : scripts/make-icon.sh
# Avec un certificat « HappytoHelp » (créé avant le renommage) dans le Trousseau, macOS reconnaît l'app d'une
# version à l'autre et garde l'accès « Accessibilité ». Sinon, signature ad hoc.
if security find-identity -p codesigning 2>/dev/null | grep -q '"HappytoHelp"'; then
    codesign --force --sign "HappytoHelp" "$APP"
else
    codesign --force --sign - "$APP"
fi

echo "OK : $APP"
