#!/usr/bin/env bash
#
# Refreshes the yt-dlp BUNDLED in the app (the seed shipped with the app).
#
# In use, the app updates itself: it installs the latest version in
# ~/Library/Application Support/TBD/bin and runs it preferentially. This
# script just prevents shipping a .app with a six-month-old seed — run before
# each release build.
#
# Usage: ./scripts/update-ytdlp.sh [stable|nightly]
#
set -euo pipefail

CHANNEL="${1:-stable}"
case "$CHANNEL" in
  stable)  REPO="yt-dlp/yt-dlp" ;;
  nightly) REPO="yt-dlp/yt-dlp-nightly-builds" ;;
  *) echo "❌ Unknown channel: $CHANNEL (expected: stable | nightly)"; exit 1 ;;
esac

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/App/Resources/bin"
ASSET="yt-dlp_macos"   # universal2 (x86_64 + arm64), ad-hoc signed at source
BASE="https://github.com/$REPO/releases/latest/download"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Braces required: attached to "…", bash would eat UTF-8 bytes in the var name
# and complain about a non-existent "ASSET…".
echo "▶ Channel $CHANNEL — downloading ${ASSET}…"
curl -fL --progress-bar -o "$TMP/$ASSET" "$BASE/$ASSET"

echo "▶ Verifying published SHA-256…"
curl -fsSL -o "$TMP/SUMS" "$BASE/SHA2-256SUMS"
EXPECTED="$(awk -v a="$ASSET" '$2 == a { print $1 }' "$TMP/SUMS")"
ACTUAL="$(shasum -a 256 "$TMP/$ASSET" | awk '{ print $1 }')"
if [ -z "$EXPECTED" ]; then
  echo "❌ No checksum published for $ASSET"; exit 1
fi
if [ "$EXPECTED" != "$ACTUAL" ]; then
  echo "❌ Corrupted download"
  echo "   expected: $EXPECTED"
  echo "   got:      $ACTUAL"
  exit 1
fi

chmod +x "$TMP/$ASSET"
# The seed is only replaced after proving the binary starts.
VERSION="$("$TMP/$ASSET" --version)"
mv "$TMP/$ASSET" "$BIN/yt-dlp"

echo "✅ yt-dlp $VERSION bundled ($CHANNEL, checksum verified)"
echo "   Rebuild the app: ./scripts/build.sh"
