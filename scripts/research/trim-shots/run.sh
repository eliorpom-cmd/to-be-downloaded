#!/usr/bin/env bash
#
# Shoots the Download screen with the Trim bar (see main.swift), off screen.
# Builds a Debug copy of the app first; the library and pending downloads in
# ~/Library/Application Support/TBD are read, never written, but are backed
# up and put back anyway.
#
# Usage: scripts/research/trim-shots/run.sh <output folder>
#
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
OUTDIR="$(mkdir -p "${1:?output folder}" && cd "$1" && pwd)"
WORK="$ROOT/build/trim-shots"
DERIVED="$WORK/DerivedData"
SUPPORT="$HOME/Library/Application Support/TBD"
mkdir -p "$WORK"

cd "$ROOT"
xcodegen generate >/dev/null
xcodebuild build -project TBD.xcodeproj -scheme TBD -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath "$DERIVED" \
  PRODUCT_BUNDLE_IDENTIFIER=com.byelior.tbd.dev CODE_SIGN_IDENTITY=- >"$WORK/build.log" 2>&1 || {
    grep -E "error:" "$WORK/build.log" | sort -u | head -20; echo "Build failed: $WORK/build.log"; exit 1; }

PRODUCTS="$DERIVED/Build/Products/Debug"
APP="$PRODUCTS/TBD.app"
xcrun swiftc -swift-version 5 -target arm64-apple-macos13.0 -o "$WORK/trim-shots" \
  -I "$PRODUCTS" "$HERE/main.swift" \
  "$APP/Contents/MacOS/TBD.debug.dylib" -Xlinker -rpath -Xlinker "$APP/Contents/MacOS" \
  >"$WORK/shots-build.log" 2>&1 || {
    grep -E "error" "$WORK/shots-build.log" | head -20; echo "Build failed: $WORK/shots-build.log"; exit 1; }
# The engine finds yt-dlp and its helpers next to the executable.
ln -sfn "$APP/Contents/Resources/bin" "$WORK/bin"

for f in library.json pending.json; do
  [ -f "$SUPPORT/$f" ] && cp -p "$SUPPORT/$f" "$WORK/$f.backup"
done
restore() {
  for f in library.json pending.json; do
    [ -f "$WORK/$f.backup" ] && cp -p "$WORK/$f.backup" "$SUPPORT/$f"
  done
}
trap restore EXIT

"$WORK/trim-shots" "$OUTDIR"
