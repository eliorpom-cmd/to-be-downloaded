#!/usr/bin/env bash
#
# Builds the app in Release, ad-hoc signs it (free, no Apple account),
# and produces a distributable DMG.
#
# Usage: ./scripts/build.sh
#
set -euo pipefail

# APP_NAME = PRODUCT_NAME from project.yml: the name of the scheme, .app, and DMG.
APP_NAME="TBD"
# Name of the volume mounted in Finder, the only place in the build where the
# acronym is spelled out — this is what someone opening the DMG sees.
VOLUME_NAME="TBD - To Be Downloaded"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED="$ROOT/build/ReleaseDerivedData"
DIST="$ROOT/dist"

cd "$ROOT"

echo "▶ Generating the Xcode project…"
xcodegen generate >/dev/null

echo "▶ Release build…"
xcodebuild -project "$APP_NAME.xcodeproj" -scheme "$APP_NAME" \
  -configuration Release -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO build >/dev/null

APP_SRC="$DERIVED/Build/Products/Release/$APP_NAME.app"
[ -d "$APP_SRC" ] || { echo "❌ App not found: $APP_SRC"; exit 1; }

echo "▶ Preparing dist/…"
rm -rf "$DIST"
mkdir -p "$DIST"
cp -R "$APP_SRC" "$DIST/"
APP="$DIST/$APP_NAME.app"

echo "▶ Ad-hoc signing (inside out)…"
# ffmpeg/ffprobe are NOT here: they are not shipped with the app. The static
# build we bundled was compiled --enable-nonfree, so legally not redistributable;
# the app downloads them on first launch from their publisher
# (cf. App/Sources/Core/FFmpegInstaller.swift).
# One name in the list today, and it stays a list: ffmpeg and ffprobe were in
# it until they stopped being shipped, and a future binary would go here.
# shellcheck disable=SC2043
for bin in yt-dlp; do
  codesign --force --sign - "$APP/Contents/Resources/bin/$bin"
done
# Extension BEFORE the app: signing the app seals the PlugIns contents, so
# signing the extension afterward would invalidate the app's signature.
for appex in "$APP/Contents/PlugIns/"*.appex; do
  [ -e "$appex" ] || continue
  codesign --force --sign - "$appex"
done
codesign --force --sign - "$APP"

echo "▶ Creating the DMG…"
STAGING="$(mktemp -d)"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
DMG="$DIST/$APP_NAME.dmg"
rm -f "$DMG"
hdiutil create -volname "$VOLUME_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGING"

echo ""
echo "✅ Done"
echo "   App: $APP"
echo "   DMG: $DMG"
echo ""
echo "ℹ️  On a DIFFERENT Mac, on first launch: right-click app → Open,"
echo "    ou en Terminal :  xattr -dr com.apple.quarantine /chemin/vers/$APP_NAME.app"
