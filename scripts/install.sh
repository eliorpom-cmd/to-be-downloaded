#!/usr/bin/env bash
#
# Installs the current version from source into /Applications.
#
# Usage: ./scripts/install.sh
#
# About macOS: there is no database of "installed software". An app is just
# a folder, and Launch Services indexes ALL copies it encounters — including those
# xcodebuild puts in build/ and Xcode itself registers on each build. That's how
# you end up with old versions in Spotlight that work fine but are stale.
#
# This script fixes it: /Applications is the ONLY installed copy, everything else
# is disposable build output, unregistered and deleted along the way.
#
set -euo pipefail

# Build product name: short with no spaces, this is what we work with in the
# repo, scripts, and Terminal.
APP_NAME="TBD"
# Bundle name ONCE INSTALLED. Different on purpose: Spotlight indexes an app by
# its FILE NAME and ignores CFBundleDisplayName — installed as "TBD" the app would
# be unfindable searching for "to be downloaded". Renaming a bundle's folder
# has no effect on its signature (which covers the contents) or the executable
# (CFBundleExecutable stays "TBD").
# LOWERCASE "downloaded", ON PURPOSE, and not a leftover. The displayed name
# is "TBD - To Be Downloaded" everywhere else since 1.1, but this is the name
# of a FOLDER already sitting in /Applications on other people's machines.
# Renaming it would leave anyone who installed from the DMG with two copies of
# the app. Spotlight searches case-insensitively, so nothing is lost by
# leaving it. See also the cask target in release.sh.
INSTALLED_NAME="TBD - To be downloaded"
BUNDLE_ID="com.byelior.tbd"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="/Applications/$INSTALLED_NAME.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"

cd "$ROOT"

# Replacing the bundle of a running app doesn't update it: the process keeps
# its old code mapped in memory (POSIX). Might as well quit it.
if /usr/bin/pgrep -x "$APP_NAME" >/dev/null 2>&1; then
  echo "▶ $APP_NAME is running, quitting it…"
  /usr/bin/osascript -e "quit app id \"$BUNDLE_ID\"" 2>/dev/null || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    /usr/bin/pgrep -x "$APP_NAME" >/dev/null 2>&1 || break
    /bin/sleep 0.5
  done
fi

"$ROOT/scripts/build.sh"

SOURCE="$ROOT/dist/$APP_NAME.app"
[ -d "$SOURCE" ] || { echo "❌ Not found after build: $SOURCE"; exit 1; }

# Braces required: attached to "…", bash would eat UTF-8 bytes in the var name.
echo "▶ Installing into ${TARGET}…"
# Remove then ditto, definitely not cp over: Launch Services' icon cache
# sticks to the old icon as long as the bundle keeps the same inode. A new
# folder forces it to reread the .icns.
rm -rf "$TARGET"
/usr/bin/ditto "$SOURCE" "$TARGET"

echo "▶ Registering with Launch Services…"
"$LSREGISTER" -f "$TARGET"

# Unregister every copy except the one in /Applications: both missing bundles
# (old build products) and those still in build/ and dist/ that the build just
# registered. They'll be back next build — hence the purge HERE, after, not before:
# when this script ends, Spotlight knows only one copy of the app.
PURGED=0
while IFS= read -r path; do
  [ "$path" = "$TARGET" ] && continue
  "$LSREGISTER" -u "$path" 2>/dev/null || true
  PURGED=$((PURGED + 1))
done < <("$LSREGISTER" -dump 2>/dev/null \
  | /usr/bin/grep -E '^path: ' \
  | /usr/bin/sed -E 's/^path:[[:space:]]+//; s/ \(0x[0-9a-f]+\)$//' \
  | /usr/bin/grep -E "/($APP_NAME|$INSTALLED_NAME)\.app$" \
  | sort -u)

# Spotlight does NOT query Launch Services' registry: it indexes the
# filesystem. An unregistered but still-present bundle will still show up
# in search. The only fix is for it not to exist.
#
# We only delete .app files, not the build folders around them: compiled
# objects live in Intermediates.noindex, and the next build stays
# incremental (re-links, doesn't recompile). The DMG is kept; Spotlight
# does not index inside an unmounted disk image.
for stray in \
  "$ROOT/dist/$APP_NAME.app" \
  "$ROOT/build/ReleaseDerivedData/Build/Products/Release/$APP_NAME.app" \
  "$ROOT/build/DebugDD/Build/Products/Debug/$APP_NAME.app"
do
  [ -d "$stray" ] || continue
  rm -rf "$stray"
done

VERSION="$(/usr/bin/defaults read "$TARGET/Contents/Info" CFBundleShortVersionString)"

echo ""
echo "✅ $INSTALLED_NAME $VERSION installed in /Applications"
[ "$PURGED" -gt 0 ] && echo "   ($PURGED parallel copy/copies unregistered from Launch Services)"
echo ""
echo "ℹ️  Copies of the app present on disk:"
/usr/bin/mdfind "kMDItemKind == 'Application'" 2>/dev/null \
  | /usr/bin/grep -E "/($APP_NAME|$INSTALLED_NAME)\.app$" | sort -u \
  | /usr/bin/sed 's/^/    /'
