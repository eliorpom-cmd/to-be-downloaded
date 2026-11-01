#!/usr/bin/env bash
#
# Refreshes the QuickJS-NG interpreter BUNDLED in the app.
#
# yt-dlp needs a JavaScript runtime to solve YouTube's n/signature challenges
# (see docs/research/2026-09-30-js-runtime.md). QuickJS-NG is 1.3 MB, MIT, and
# ships inside the app so that it works offline, on first launch. Unlike
# yt-dlp it is not updated by the app: it moves with app releases.
#
# QuickJS-NG publishes NO checksum file, so the SHA-256 of each version is
# pinned below and must be updated deliberately, after downloading the new
# asset by hand and checking where it came from.
#
# arm64 only: FFmpeg is installed for arm64 too, so the app does not download
# anything on an Intel Mac. If `qjs` cannot start, yt-dlp just runs without it.
#
# Usage: ./scripts/update-qjs.sh
#
set -euo pipefail

VERSION="v0.17.0"
SHA256="8be3ddfe3397d2e692e4e1e8972ee9d032a0a580505d2f8b4ea528cf1b651c11"
ASSET="qjs-darwin-arm64"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/App/Resources/bin"
URL="https://github.com/quickjs-ng/quickjs/releases/download/$VERSION/$ASSET"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "▶ QuickJS-NG $VERSION — downloading ${ASSET}…"
curl -fL --progress-bar -o "$TMP/qjs" "$URL"

ACTUAL="$(shasum -a 256 "$TMP/qjs" | awk '{ print $1 }')"
if [ "$ACTUAL" != "$SHA256" ]; then
  echo "❌ Checksum mismatch for $ASSET $VERSION"
  echo "   expected: $SHA256"
  echo "   got:      $ACTUAL"
  exit 1
fi

chmod +x "$TMP/qjs"
# The downloaded file carries a quarantine attribute that stops it running.
xattr -c "$TMP/qjs" 2>/dev/null || true
# The file must be named `qjs`: that is the name yt-dlp looks for when given a
# directory, and the name the app passes.
"$TMP/qjs" --help >/dev/null 2>&1 || { echo "❌ qjs does not start"; exit 1; }
mv "$TMP/qjs" "$BIN/qjs"

echo "✅ QuickJS-NG $VERSION bundled (checksum pinned)"
