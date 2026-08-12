#!/usr/bin/env bash
#
# Retakes the screenshots used by the README and the website.
#
# Usage: ./scripts/screenshots.sh [--repo-only|--site-only] [--keep-desktop]
#
# What it does: hides every other app, puts the window at a fixed size in the
# middle of the screen, walks the sidebar, and shoots. The repository shots are
# the window alone; the website shots keep the wallpaper around it.
#
# Two things it deliberately does NOT do. It starts no download — a still
# window is a fine screenshot, and waiting on the network would make the
# result different every time. And it does not empty or fill the Library: what
# is in there is what the Library shot shows, so put a few downloads in it
# first if you want it to look like something.
#
# Needs: the app installed and past its setup screens, and Accessibility
# permission for whichever terminal runs this (System Settings ▸ Privacy &
# Security ▸ Accessibility). Without it, nothing can drive the window.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="/Applications/TBD - To be downloaded.app"
BUNDLE_ID="com.byelior.tbd"
HIDE_DESKTOP_ICONS=1
DRIVER_ARGS=()

for arg in "$@"; do
  case "$arg" in
    --keep-desktop) HIDE_DESKTOP_ICONS=0 ;;
    *) DRIVER_ARGS+=("$arg") ;;
  esac
done

cd "$ROOT"

[ -d "$APP" ] || { echo "❌ Not installed: $APP — run ./scripts/install.sh"; exit 1; }

# Desktop icons are somebody's private filing cabinet, and they end up in every
# website shot. Hidden for the duration and restored by the trap below, which
# runs on success, on failure and on Ctrl-C alike — leaving someone's desktop
# empty would be a memorable way to fail.
restore_desktop() {
  if [ "$HIDE_DESKTOP_ICONS" -eq 1 ]; then
    defaults write com.apple.finder CreateDesktop true
    killall Finder 2>/dev/null || true
  fi
}
if [ "$HIDE_DESKTOP_ICONS" -eq 1 ]; then
  trap restore_desktop EXIT INT TERM
  echo "▶ Hiding desktop icons…"
  defaults write com.apple.finder CreateDesktop false
  killall Finder 2>/dev/null || true
  sleep 2
fi

if ! /usr/bin/pgrep -x TBD >/dev/null 2>&1; then
  echo "▶ Launching the app…"
  /usr/bin/open -a "$APP"
  sleep 5
fi

# Compiled to a temporary file rather than run through `swift`, which is
# several seconds slower every time and prints its own noise.
DRIVER="$(/usr/bin/mktemp -t tbd-screenshots)"
trap 'rm -f "$DRIVER"; restore_desktop' EXIT INT TERM
echo "▶ Building the driver…"
/usr/bin/xcrun swiftc -O "$ROOT/scripts/screenshots.swift" -o "$DRIVER"

echo "▶ Shooting…"
if [ ${#DRIVER_ARGS[@]} -gt 0 ]; then
  "$DRIVER" "${DRIVER_ARGS[@]}"
else
  "$DRIVER"
fi

echo ""
echo "✅ Done. Check them before committing: $BUNDLE_ID moves on, and a shot"
echo "   taken while a dialog was open looks fine to a script."
