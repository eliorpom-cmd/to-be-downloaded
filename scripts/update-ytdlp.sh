#!/usr/bin/env bash
#
# Met à jour le yt-dlp embarqué vers la dernière version.
# À lancer quand YouTube casse les téléchargements (yt-dlp évolue vite).
# Ensuite : reconstruire l'app avec ./scripts/build.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/App/Resources/bin"

echo "▶ Téléchargement de la dernière version de yt-dlp…"
curl -L -sS -o "$BIN/yt-dlp" \
  "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos"
chmod +x "$BIN/yt-dlp"

echo "✅ yt-dlp $("$BIN/yt-dlp" --version)"
echo "   Reconstruis l'app :  ./scripts/build.sh"
