#!/usr/bin/env bash
#
# Construit l'app en Release, la signe en ad-hoc (gratuit, sans compte Apple)
# et produit un DMG distribuable.
#
# Usage :  ./scripts/build.sh
#
set -euo pipefail

APP_NAME="Downloader"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED="$ROOT/build/ReleaseDerivedData"
DIST="$ROOT/dist"

cd "$ROOT"

echo "▶ Génération du projet Xcode…"
xcodegen generate >/dev/null

echo "▶ Compilation Release…"
xcodebuild -project "$APP_NAME.xcodeproj" -scheme "$APP_NAME" \
  -configuration Release -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO build >/dev/null

APP_SRC="$DERIVED/Build/Products/Release/$APP_NAME.app"
[ -d "$APP_SRC" ] || { echo "❌ App introuvable : $APP_SRC"; exit 1; }

echo "▶ Préparation de dist/…"
rm -rf "$DIST"
mkdir -p "$DIST"
cp -R "$APP_SRC" "$DIST/"
APP="$DIST/$APP_NAME.app"

echo "▶ Signature ad-hoc (binaires embarqués, puis l'app)…"
for bin in yt-dlp ffmpeg ffprobe; do
  codesign --force --sign - "$APP/Contents/Resources/bin/$bin"
done
codesign --force --sign - "$APP"

echo "▶ Création du DMG…"
STAGING="$(mktemp -d)"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
DMG="$DIST/$APP_NAME.dmg"
rm -f "$DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGING"

echo ""
echo "✅ Terminé"
echo "   App : $APP"
echo "   DMG : $DMG"
echo ""
echo "ℹ️  Sur un AUTRE Mac, au 1er lancement : clic droit sur l'app → Ouvrir,"
echo "    ou en Terminal :  xattr -dr com.apple.quarantine /chemin/vers/$APP_NAME.app"
