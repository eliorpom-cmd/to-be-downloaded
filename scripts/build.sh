#!/usr/bin/env bash
#
# Builds the app in Release, signs it, and produces a distributable DMG.
#
# Usage: ./scripts/build.sh
#
# Two signing modes, picked automatically:
#
#   Developer ID  — a "Developer ID Application" identity is in the keychain.
#                   Hardened runtime, secure timestamp, entitlements, then
#                   notarization and stapling if notary credentials exist.
#                   This is what ships.
#   ad-hoc        — no such identity. Signs with `-`, which is enough to run
#                   on this Mac but is refused by Gatekeeper anywhere else.
#                   This is what the project did before the paid account, and
#                   it stays so that a contributor without one can still build.
#
# Overrides:
#   TBD_SIGN_IDENTITY   the identity to sign with ("-" forces ad-hoc)
#   TBD_NOTARY_PROFILE  notarytool keychain profile (default: tbd-notary)
#   TBD_SKIP_NOTARIZE   set to 1 to sign Developer ID without notarizing
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
NOTARY_PROFILE="${TBD_NOTARY_PROFILE:-tbd-notary}"

cd "$ROOT"

# ── Which identity? ──────────────────────────────────────────────────────────
# Note "Developer ID Application" and not "Apple Development": a development
# certificate is in the keychain of anyone who ever opened Xcode, expires after
# a year, and passes Gatekeeper no better than an ad-hoc signature. Picking it
# up by accident would ship an app that stops working on a date nobody wrote
# down. Hence matching the exact prefix rather than taking the first identity.
if [ -n "${TBD_SIGN_IDENTITY:-}" ]; then
  IDENTITY="$TBD_SIGN_IDENTITY"
else
  IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | /usr/bin/grep 'Developer ID Application' \
    | /usr/bin/head -1 \
    | /usr/bin/sed -E 's/.*"(.*)".*/\1/')"
  IDENTITY="${IDENTITY:--}"
fi

if [ "$IDENTITY" = "-" ]; then
  SIGN_MODE="adhoc"
  # No --options runtime: the hardened runtime is required by notarization and
  # by nothing else, and it breaks the frozen yt-dlp without entitlements the
  # ad-hoc path has no reason to carry.
  SIGN_FLAGS=()
else
  SIGN_MODE="developer-id"
  # --timestamp is not optional: notarization rejects a signature without a
  # secure timestamp, and it is the single most common cause of rejection.
  SIGN_FLAGS=(--options runtime --timestamp)
fi

echo "▶ Generating the Xcode project…"
xcodegen generate >/dev/null

echo "▶ Release build…"
# CODE_SIGNING_ALLOWED=NO: signing is a step of this script, not a side effect
# of Xcode choosing an identity from the keychain. Consequence to keep in mind
# — CODE_SIGN_ENTITLEMENTS in project.yml is then never applied by Xcode, so
# every --entitlements below is load-bearing rather than belt-and-braces.
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

echo "▶ Signing ($SIGN_MODE: $IDENTITY)…"
# ffmpeg/ffprobe are NOT here: they are not shipped with the app. The static
# build we bundled was compiled --enable-nonfree, so legally not redistributable;
# the app downloads them on first launch from their publisher
# (cf. App/Sources/Core/FFmpegInstaller.swift).
# One name in the list today, and it stays a list: ffmpeg and ffprobe were in
# it until they stopped being shipped, and a future binary would go here.
# shellcheck disable=SC2043
for bin in yt-dlp; do
  # Its own entitlements, and only its own: a PyInstaller binary needs
  # executable memory and unvalidated libraries, the app does not.
  codesign --force --sign "$IDENTITY" "${SIGN_FLAGS[@]+"${SIGN_FLAGS[@]}"}" \
    --entitlements "$ROOT/App/ytdlp.entitlements" \
    "$APP/Contents/Resources/bin/$bin"
done
# Extension BEFORE the app: signing the app seals the PlugIns contents, so
# signing the extension afterward would invalidate the app's signature.
for appex in "$APP/Contents/PlugIns/"*.appex; do
  [ -e "$appex" ] || continue
  codesign --force --sign "$IDENTITY" "${SIGN_FLAGS[@]+"${SIGN_FLAGS[@]}"}" \
    --entitlements "$ROOT/Extension/Share/Share.entitlements" \
    "$appex"
done
codesign --force --sign "$IDENTITY" "${SIGN_FLAGS[@]+"${SIGN_FLAGS[@]}"}" \
  --entitlements "$ROOT/App/TBD.entitlements" \
  "$APP"

# Fails here rather than on a stranger's machine.
codesign --verify --deep --strict -vv "$APP" 2>&1 | /usr/bin/sed 's/^/   /'

# ── Notarization ─────────────────────────────────────────────────────────────
# Only Apple can turn a signature into something Gatekeeper accepts. Without
# this step a Developer ID signature is worth exactly as much as an ad-hoc one
# to someone who downloaded the app — which is the part of this that surprises
# everybody.
notarize() {
  # Declared on separate lines: `local a=$1 b=$a` does not see `a` reliably —
  # `local` creates every name before it runs the assignments.
  local target="$1"
  local kind="$2"
  local payload="$target"
  # notarytool only takes .zip, .dmg and .pkg. A .app has to be zipped first,
  # with ditto — `zip` drops the extended attributes and the signature.
  if [ "$kind" = "app" ]; then
    payload="$DIST/notarize-$APP_NAME.zip"
    rm -f "$payload"
    /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$target" "$payload"
  fi

  # Output to a file and echoed afterwards, rather than piped into sed. Piping
  # puts notarytool's exit status behind `pipefail`, and a failed submission
  # then kills the script on a line whose message nobody ever sees — which is
  # a genuinely miserable half hour when it happens.
  local log="$DIST/notarize-$kind.log"
  local rc=0
  xcrun notarytool submit "$payload" \
    --keychain-profile "$NOTARY_PROFILE" --wait >"$log" 2>&1 || rc=$?
  /usr/bin/sed 's/^/   /' "$log"
  [ "$kind" = "app" ] && rm -f "$payload"
  if [ "$rc" -ne 0 ] || ! /usr/bin/grep -q "status: Accepted" "$log"; then
    echo "❌ Notarization refused. The full report says why:"
    local id
    id="$(/usr/bin/grep -m1 '  id:' "$log" | /usr/bin/awk '{print $2}')"
    [ -n "$id" ] && echo "   xcrun notarytool log $id --keychain-profile $NOTARY_PROFILE"
    return 1
  fi

  # Stapling writes Apple's ticket INTO the bundle, so the machine that opens
  # it does not need the network to know it was notarized. Skipping it means
  # a first launch with no network is refused.
  #
  # Retried, because the first attempt right after a submission is accepted
  # routinely fails with "Error 68" and a CloudKit complaint: the ticket exists
  # but is not being served yet. It is a transient that looks exactly like a
  # hard failure, and on a machine behind a TLS interceptor (parental controls,
  # corporate proxy) it shows up more often.
  local attempt
  for attempt in 1 2 3 4 5; do
    if xcrun stapler staple "$target" 2>&1 | /usr/bin/sed 's/^/   /'; then
      xcrun stapler validate "$target" >/dev/null 2>&1 && return 0
    fi
    echo "   stapling failed (attempt $attempt), retrying…"
    /bin/sleep 15
  done
  echo "❌ Could not staple $target after 5 attempts."
  echo "   Gatekeeper may still accept it online, but a first launch offline"
  echo "   would be refused. Do not publish this build."
  return 1
}

NOTARIZED="no"
if [ "$SIGN_MODE" = "developer-id" ] && [ "${TBD_SKIP_NOTARIZE:-}" != "1" ]; then
  if xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    echo "▶ Notarizing the app (a few minutes)…"
    notarize "$APP" app
    NOTARIZED="yes"
  else
    echo "⚠️  No notarytool profile '$NOTARY_PROFILE' — signed but NOT notarized."
    echo "    xcrun notarytool store-credentials $NOTARY_PROFILE \\"
    echo "      --key <AuthKey.p8> --key-id <KEY_ID> --issuer <ISSUER_ID>"
  fi
fi

echo "▶ Creating the DMG…"
STAGING="$(mktemp -d)"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
DMG="$DIST/$APP_NAME.dmg"
rm -f "$DMG"
hdiutil create -volname "$VOLUME_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGING"

# The disk image gets signed too, and not only notarized. Stapling a ticket to
# an unsigned image leaves `spctl -a -t open --context context:primary-signature`
# answering "no usable signature", which is not what you want to discover from
# someone else's screenshot. Signing it first is what Apple documents.
if [ "$SIGN_MODE" = "developer-id" ]; then
  codesign --force --sign "$IDENTITY" --timestamp "$DMG"
fi

# The DMG is notarized and stapled separately from the app it carries. The two
# tickets are not the same thing: without this one, the disk image itself is
# what Gatekeeper refuses, before anyone gets to the app inside it.
if [ "$NOTARIZED" = "yes" ]; then
  echo "▶ Notarizing the DMG…"
  notarize "$DMG" dmg
fi

echo ""
echo "✅ Done"
echo "   App: $APP"
echo "   DMG: $DMG"
echo "   Signature: $SIGN_MODE, notarized: $NOTARIZED"
echo ""
if [ "$NOTARIZED" = "yes" ]; then
  echo "ℹ️  Opens straight on any Mac. To prove it rather than hope so:"
  echo "    spctl -a -vvv \"$APP\"        → accepted, source=Notarized Developer ID"
  echo "    xcrun stapler validate \"$DMG\""
else
  echo "ℹ️  On a DIFFERENT Mac, this build is refused by Gatekeeper. To open it:"
  echo "    xattr -dr com.apple.quarantine /path/to/$APP_NAME.app"
fi
