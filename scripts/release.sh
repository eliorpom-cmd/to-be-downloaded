#!/usr/bin/env bash
#
# Publishes a release: Release build → Ed25519-signed ZIP archive → Homebrew cask.
#
# Usage: ./scripts/release.sh 0.2.0 [backup]
#
# "backup" signs with the backup key instead of the current key (useful if the
# current is lost: both public keys are accepted by the app).
#
# The script publishes NOTHING by itself: it prepares everything in dist/ and
# displays the `gh release create` command to run. Publishing stays explicit.
#
# What users will then get automatically: the installed app checks this
# repository for releases once a day, rejects any archive whose Ed25519
# signature doesn't match the public key compiled in the app
# (AppConfig.updatePublicKey), and replaces its own bundle.
#
set -euo pipefail

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
  echo "Usage: ./scripts/release.sh <version>   (e.g. 0.2.0)"; exit 1
fi
if ! printf '%s' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "❌ Expected a version in X.Y.Z form (got: $VERSION)"; exit 1
fi

KEY_KIND="${2:-}"   # "" (current key) or "backup"

APP_NAME="TBD"
# Cask token = what the user types after the tap. Spelled out because you type
# it only once and it must be guessable:
#   brew install --cask eliorpom-cmd/tap/to-be-downloaded
CASK_TOKEN="to-be-downloaded"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
ZIP_NAME="$APP_NAME-$VERSION-macos.zip"

cd "$ROOT"

# Repository deduced from git remote: renaming the repo doesn't require
# editing this script (only AppConfig.updateRepository needs updating).
REPO="$(git remote get-url origin 2>/dev/null \
  | /usr/bin/sed -E 's#^git@github.com:##; s#^https://github.com/##; s#\.git$##')"
if [ -z "$REPO" ]; then
  echo "❌ Cannot deduce the GitHub repository from 'git remote get-url origin'"; exit 1
fi

APP_REPO="$(/usr/bin/grep -o 'updateRepository = "[^"]*"' App/Sources/AppConfig.swift \
  | /usr/bin/sed 's/.*"\(.*\)"/\1/')"
if [ "$REPO" != "$APP_REPO" ]; then
  echo "❌ The remote repository ($REPO) and the one compiled into the app ($APP_REPO) differ."
  echo "   → Update AppConfig.updateRepository, otherwise the app will look for"
  echo "     its updates in the wrong place."
  exit 1
fi

echo "▶ Version $VERSION in project.yml…"
/usr/bin/sed -i '' -E "s/MARKETING_VERSION: \"[^\"]*\"/MARKETING_VERSION: \"$VERSION\"/" project.yml
BUILD_NUMBER="$(/bin/date +%Y%m%d%H%M)"
/usr/bin/sed -i '' -E "s/CURRENT_PROJECT_VERSION: \"[^\"]*\"/CURRENT_PROJECT_VERSION: \"$BUILD_NUMBER\"/" project.yml

echo "▶ Bundled yt-dlp: latest stable version…"
"$ROOT/scripts/update-ytdlp.sh" stable >/dev/null

echo "▶ Build Release + signature + DMG…"
"$ROOT/scripts/build.sh"

APP="$DIST/$APP_NAME.app"
[ -d "$APP" ] || { echo "❌ App not found after build: $APP"; exit 1; }

# Is what we just built actually notarized? Asked of the artifact, never
# assumed: the cask's caveats tell users whether they must run a raw `xattr`
# command, and getting that wrong is either an install nobody can complete or
# a pointless security warning on a perfectly fine app.
if xcrun stapler validate "$APP" >/dev/null 2>&1; then
  NOTARIZED="yes"
else
  NOTARIZED="no"
  echo "⚠️  This build is NOT notarized: the cask will keep the xattr caveat"
  echo "    and everyone installing it will have to run that command."
fi

# The version IN the bundle must match the release: the updater rejects
# an archive whose Info.plist announces anything different than the tag.
SHIPPED="$(/usr/bin/defaults read "$APP/Contents/Info" CFBundleShortVersionString)"
if [ "$SHIPPED" != "$VERSION" ]; then
  echo "❌ The bundle announces $SHIPPED instead of $VERSION"; exit 1
fi

# Braces required: attached to "…", bash would eat UTF-8 bytes in the var name.
echo "▶ Archive ${ZIP_NAME}…"
# ditto (not zip): preserves permissions, extended attributes, and the bundle's
# ad-hoc signature. It will also extract it on the client side.
rm -f "$DIST/$ZIP_NAME" "$DIST/$ZIP_NAME.sig"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP" "$DIST/$ZIP_NAME"

echo "▶ Ed25519 signature (${KEY_KIND:-current} key)…"
# $KEY_KIND is deliberately unquoted: it is empty for the current key, and
# quoting it would pass an empty argument that signing.swift would read as a
# key kind it does not know.
# shellcheck disable=SC2086
"$ROOT/scripts/signing.swift" sign "$DIST/$ZIP_NAME" $KEY_KIND >/dev/null
# shellcheck disable=SC2086
PUBKEY="$("$ROOT/scripts/signing.swift" pubkey $KEY_KIND)"
"$ROOT/scripts/signing.swift" verify "$DIST/$ZIP_NAME" "$DIST/$ZIP_NAME.sig" "$PUBKEY"

# Safeguard: signing with a key that installed apps don't know about would
# break updates for users. So we verify that the key used is among those
# compiled in the app.
if ! /usr/bin/grep -q "$PUBKEY" App/Sources/AppConfig.swift; then
  echo "❌ The key used is not in AppConfig.updatePublicKeys:"
  echo "   $PUBKEY"
  echo "   → Already-installed apps could NOT validate this release."
  exit 1
fi

SHA="$(/usr/bin/shasum -a 256 "$DIST/$ZIP_NAME" | /usr/bin/awk '{print $1}')"

if [ "$NOTARIZED" = "yes" ]; then
  # Signed and notarized: nothing for the user to do, and nothing to say. An
  # empty caveats block would still print a header, so there is none at all.
  CAVEATS=""
else
  # `read -d ''` and not $(cat <<…): bash 3.2, which is what /bin/bash still is
  # on macOS, cannot parse a heredoc inside a command substitution.
  IFS='' read -r -d '' CAVEATS <<'CAV' || true

  caveats <<~EOS
    This app is signed ad-hoc and is not notarised by Apple, so macOS
    quarantines it and refuses to open it. Homebrew dropped --no-quarantine in
    5.1, so the attribute has to come off by hand, once:

      xattr -dr com.apple.quarantine "/Applications/TBD - To be downloaded.app"

    Updates afterwards are automatic and are verified against the developer's
    Ed25519 key before anything is installed.
  EOS
CAV
fi

echo "▶ Cask Homebrew…"
# Everything below until CASK is the cask, verbatim, with the shell expanding
# $VERSION and friends — which is why the heredoc is unquoted.
#
# Consequence, and it has bitten once: a backtick pair in here is command
# substitution, comments included. Writing `verified:` in a comment ran it as a
# command, printed "command not found", and shipped the comment gutted. Quotes
# in this block, never backticks.
cat > "$DIST/$CASK_TOKEN.rb" <<CASK
cask "$CASK_TOKEN" do
  version "$VERSION"
  sha256 "$SHA"

  # No "verified" stanza: Homebrew 7 deprecates it and warns on every command
  # that touches the cask. It existed to vouch for a URL whose host does not
  # match the homepage; here they are the same GitHub repository, which is
  # exactly the case the default verification already covers.
  url "https://github.com/$REPO/releases/download/v#{version}/$APP_NAME-#{version}-macos.zip"
  name "TBD - To Be Downloaded"
  name "TBD"
  desc "Downloads YouTube video and audio, with a LAN web remote"
  homepage "https://github.com/$REPO"

  # The app updates itself (Ed25519-signed releases), so Homebrew shouldn't
  # worry about seeing a newer version than its own.
  auto_updates true
  # A bare symbol means "this version or newer". The ">= :ventura" string form
  # is deprecated since Homebrew 6 and warns on every tap.
  depends_on macos: :ventura

  # Installed with the full name: Spotlight indexes an app by its FILE NAME
  # and ignores CFBundleDisplayName. Under "TBD.app" the app would be unfound
  # searching for "to be downloaded".
  # Lowercase "downloaded" on purpose: this is an existing path on other
  # people's disks, not a label. Renaming it is how you give someone two apps.
  app "$APP_NAME.app", target: "TBD - To be downloaded.app"
$CAVEATS
  zap trash: [
    "~/Library/Application Support/$APP_NAME",
    "~/Library/Preferences/com.byelior.tbd.plist",
    "~/Library/Saved Application State/com.byelior.tbd.savedState",
  ]
end
CASK

echo ""
echo "✅ Ready in dist/"
echo "   $ZIP_NAME        ($(/usr/bin/du -h "$DIST/$ZIP_NAME" | /usr/bin/awk '{print $1}'))"
echo "   $ZIP_NAME.sig    (Ed25519 signature)"
echo "   $APP_NAME.dmg              (direct download)"
echo "   $CASK_TOKEN.rb    (Homebrew cask, sha256 $SHA)"
echo ""
echo "1) Publish the release:"
echo ""
# The DMG ships under its bare name, never versioned: the site links it through
# `releases/latest/download/TBD.dmg`, and a version in the filename would break
# that link on every release. The ZIP keeps its version because the cask builds
# its URL from the version it declares.
echo "   gh release create v$VERSION \\"
echo "     \"$DIST/$ZIP_NAME\" \\"
echo "     \"$DIST/$ZIP_NAME.sig\" \\"
echo "     \"$DIST/$APP_NAME.dmg\" \\"
echo "     --repo $REPO --title \"v$VERSION\" --notes \"…\""
echo ""
echo "2) Update the tap (repo eliorpom-cmd/homebrew-tap):"
echo ""
echo "   cp \"$DIST/$CASK_TOKEN.rb\" <tap-clone>/Casks/$CASK_TOKEN.rb"
echo "   # then commit + push"
echo ""
echo "ℹ️  Both the ZIP and the .sig must be attached to the release:"
echo "    without the .sig, installed apps will refuse the update."
