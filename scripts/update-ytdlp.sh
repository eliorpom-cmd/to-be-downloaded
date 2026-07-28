#!/usr/bin/env bash
#
# Rafraîchit le yt-dlp EMBARQUÉ dans le bundle (l'amorce livrée avec l'app).
#
# À l'usage, l'app se met à jour toute seule : elle installe la dernière version
# dans ~/Library/Application Support/TBD/bin et l'exécute en priorité.
# Ce script ne sert donc qu'à ne pas distribuer un .app dont l'amorce a six mois
# — à lancer avant chaque build de release.
#
# Usage :  ./scripts/update-ytdlp.sh [stable|nightly]
#
set -euo pipefail

CHANNEL="${1:-stable}"
case "$CHANNEL" in
  stable)  REPO="yt-dlp/yt-dlp" ;;
  nightly) REPO="yt-dlp/yt-dlp-nightly-builds" ;;
  *) echo "❌ Canal inconnu : $CHANNEL (attendu : stable | nightly)"; exit 1 ;;
esac

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/App/Resources/bin"
ASSET="yt-dlp_macos"   # universal2 (x86_64 + arm64), signé ad-hoc à la source
BASE="https://github.com/$REPO/releases/latest/download"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Accolades obligatoires : collé à « … », bash avale les octets UTF-8 dans le
# nom de variable et se plaint d'un « ASSET… » inexistant.
echo "▶ Canal $CHANNEL — téléchargement de ${ASSET}…"
curl -fL --progress-bar -o "$TMP/$ASSET" "$BASE/$ASSET"

echo "▶ Vérification du SHA-256 publié…"
curl -fsSL -o "$TMP/SUMS" "$BASE/SHA2-256SUMS"
EXPECTED="$(awk -v a="$ASSET" '$2 == a { print $1 }' "$TMP/SUMS")"
ACTUAL="$(shasum -a 256 "$TMP/$ASSET" | awk '{ print $1 }')"
if [ -z "$EXPECTED" ]; then
  echo "❌ Aucune somme publiée pour $ASSET"; exit 1
fi
if [ "$EXPECTED" != "$ACTUAL" ]; then
  echo "❌ Téléchargement corrompu"
  echo "   attendu : $EXPECTED"
  echo "   obtenu  : $ACTUAL"
  exit 1
fi

chmod +x "$TMP/$ASSET"
# L'amorce n'est remplacée qu'après avoir prouvé que le binaire démarre.
VERSION="$("$TMP/$ASSET" --version)"
mv "$TMP/$ASSET" "$BIN/yt-dlp"

echo "✅ yt-dlp $VERSION embarqué ($CHANNEL, somme vérifiée)"
echo "   Reconstruis l'app :  ./scripts/build.sh"
