#!/usr/bin/env bash
#
# Builds and runs the Trim drag benchmark (see main.swift) against the
# current sources. Nothing is shown on screen.
#
# Usage: scripts/research/trim-drag-bench/run.sh <yt-dlp --dump-single-json output>
#
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
S="$ROOT/App/Sources"
OUT="$ROOT/build/trim-drag-bench"
mkdir -p "$(dirname "$OUT")"

xcrun swiftc -O -swift-version 5 -target arm64-apple-macos13.0 -o "$OUT" \
  "$HERE/main.swift" \
  "$S/AppConfig.swift" "$S/Theme.swift" "$S/Formatting.swift" \
  "$S/Core/BinaryLocator.swift" "$S/Core/BrowserCookies.swift" "$S/Core/ClipRange.swift" \
  "$S/Core/DownloadEngine.swift" "$S/Core/DownloadJob.swift" "$S/Core/DownloadFormat.swift" \
  "$S/Core/DownloadProgress.swift" "$S/Core/FilenameTemplate.swift" "$S/Core/MediaMetadata.swift" \
  "$S/Core/Playlist.swift" "$S/Core/ProblemReport.swift" "$S/Core/ProcessRunner.swift" \
  "$S/Core/YouTubeLink.swift" "$S/Server/APIModels.swift" \
  "$S/Views/TrimEditor.swift" >"$OUT.log" 2>&1 || {
    grep -E "error" "$OUT.log" | head -20; echo "Build failed: $OUT.log"; exit 1; }

"$OUT" "${1:?metadata.json}"
