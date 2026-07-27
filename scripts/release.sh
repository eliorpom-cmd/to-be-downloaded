#!/usr/bin/env bash
#
# Publie une version : build Release → archive ZIP signée Ed25519 → cask Homebrew.
#
# Usage :  ./scripts/release.sh 0.2.0 [backup]
#
# « backup » signe avec la clé de secours au lieu de la clé courante (utile si
# celle-ci est perdue : les deux clés publiques sont acceptées par l'app).
#
# Le script ne publie RIEN tout seul : il prépare tout dans dist/ et affiche la
# commande `gh release create` à lancer. Publier reste une décision explicite.
#
# Ce que les utilisateurs recevront ensuite automatiquement : l'app installée
# vérifie une fois par jour les releases de ce dépôt, refuse toute archive dont
# la signature Ed25519 ne correspond pas à la clé publique compilée dans
# l'app (AppConfig.updatePublicKey), et remplace son propre bundle.
#
set -euo pipefail

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
  echo "Usage : ./scripts/release.sh <version>   (ex. 0.2.0)"; exit 1
fi
if ! printf '%s' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "❌ Version attendue au format X.Y.Z (reçu : $VERSION)"; exit 1
fi

KEY_KIND="${2:-}"   # "" (clé courante) ou "backup"

APP_NAME="Downloader"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
ZIP_NAME="$APP_NAME-$VERSION-macos.zip"

cd "$ROOT"

# Dépôt déduit du remote git : renommer le dépôt ne demande donc pas de toucher
# à ce script (seul AppConfig.updateRepository reste à mettre à jour).
REPO="$(git remote get-url origin 2>/dev/null \
  | /usr/bin/sed -E 's#^git@github.com:##; s#^https://github.com/##; s#\.git$##')"
if [ -z "$REPO" ]; then
  echo "❌ Impossible de déduire le dépôt GitHub depuis 'git remote get-url origin'"; exit 1
fi

APP_REPO="$(/usr/bin/grep -o 'updateRepository = "[^"]*"' App/Sources/AppConfig.swift \
  | /usr/bin/sed 's/.*"\(.*\)"/\1/')"
if [ "$REPO" != "$APP_REPO" ]; then
  echo "❌ Le dépôt du remote ($REPO) et celui compilé dans l'app ($APP_REPO) diffèrent."
  echo "   → Mets à jour AppConfig.updateRepository, sinon l'app ira chercher"
  echo "     ses mises à jour au mauvais endroit."
  exit 1
fi

echo "▶ Version $VERSION dans project.yml…"
/usr/bin/sed -i '' -E "s/MARKETING_VERSION: \"[^\"]*\"/MARKETING_VERSION: \"$VERSION\"/" project.yml
BUILD_NUMBER="$(/bin/date +%Y%m%d%H%M)"
/usr/bin/sed -i '' -E "s/CURRENT_PROJECT_VERSION: \"[^\"]*\"/CURRENT_PROJECT_VERSION: \"$BUILD_NUMBER\"/" project.yml

echo "▶ yt-dlp embarqué : dernière version stable…"
"$ROOT/scripts/update-ytdlp.sh" stable >/dev/null

echo "▶ Build Release + signature ad-hoc + DMG…"
"$ROOT/scripts/build.sh" >/dev/null

APP="$DIST/$APP_NAME.app"
[ -d "$APP" ] || { echo "❌ App introuvable après build : $APP"; exit 1; }

# La version DANS le bundle doit correspondre à la release : l'updater refuse
# une archive dont l'Info.plist annonce autre chose que le tag.
SHIPPED="$(/usr/bin/defaults read "$APP/Contents/Info" CFBundleShortVersionString)"
if [ "$SHIPPED" != "$VERSION" ]; then
  echo "❌ Le bundle annonce $SHIPPED au lieu de $VERSION"; exit 1
fi

# Accolades obligatoires : collé à « … », bash avale les octets UTF-8 dans le
# nom de la variable.
echo "▶ Archive ${ZIP_NAME}…"
# ditto (et pas zip) : préserve permissions, attributs étendus et signature
# ad-hoc du bundle. C'est aussi ditto qui l'extraira côté client.
rm -f "$DIST/$ZIP_NAME" "$DIST/$ZIP_NAME.sig"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP" "$DIST/$ZIP_NAME"

echo "▶ Signature Ed25519 (clé ${KEY_KIND:-courante})…"
"$ROOT/scripts/signing.swift" sign "$DIST/$ZIP_NAME" $KEY_KIND >/dev/null
PUBKEY="$("$ROOT/scripts/signing.swift" pubkey $KEY_KIND)"
"$ROOT/scripts/signing.swift" verify "$DIST/$ZIP_NAME" "$DIST/$ZIP_NAME.sig" "$PUBKEY"

# Garde-fou : signer avec une clé que les apps installées ne connaissent pas
# rendrait la mise à jour impossible chez les utilisateurs. On vérifie donc que
# la clé utilisée figure bien parmi celles compilées dans l'app.
if ! /usr/bin/grep -q "$PUBKEY" App/Sources/AppConfig.swift; then
  echo "❌ La clé utilisée n'est pas dans AppConfig.updatePublicKeys :"
  echo "   $PUBKEY"
  echo "   → Les apps déjà installées ne pourraient PAS valider cette release."
  exit 1
fi

SHA="$(/usr/bin/shasum -a 256 "$DIST/$ZIP_NAME" | /usr/bin/awk '{print $1}')"

echo "▶ Cask Homebrew…"
cat > "$DIST/downloader.rb" <<CASK
cask "downloader" do
  version "$VERSION"
  sha256 "$SHA"

  url "https://github.com/$REPO/releases/download/v#{version}/$APP_NAME-#{version}-macos.zip",
      verified: "github.com/$REPO/"
  name "$APP_NAME"
  desc "Downloads YouTube video and audio, with a LAN web remote"
  homepage "https://github.com/$REPO"

  # L'app se met à jour elle-même (releases signées Ed25519), donc Homebrew ne
  # doit pas s'inquiéter de voir une version plus récente que la sienne.
  auto_updates true
  depends_on macos: ">= :ventura"

  app "$APP_NAME.app"

  caveats <<~EOS
    This app is signed ad-hoc, not notarised by Apple, so install it with
    --no-quarantine (otherwise macOS refuses to open it):

      brew install --cask --no-quarantine eliorpom-cmd/tap/downloader

    Updates afterwards are automatic and are verified against the developer's
    Ed25519 key before anything is installed.
  EOS

  zap trash: [
    "~/Library/Application Support/$APP_NAME",
    "~/Library/Preferences/com.local.downloader.plist",
    "~/Library/Saved Application State/com.local.downloader.savedState",
  ]
end
CASK

echo ""
echo "✅ Prêt dans dist/"
echo "   $ZIP_NAME        ($(/usr/bin/du -h "$DIST/$ZIP_NAME" | /usr/bin/awk '{print $1}'))"
echo "   $ZIP_NAME.sig    (signature Ed25519)"
echo "   downloader.rb    (cask Homebrew, sha256 $SHA)"
echo ""
echo "1) Publier la release :"
echo ""
echo "   gh release create v$VERSION \\"
echo "     \"$DIST/$ZIP_NAME\" \\"
echo "     \"$DIST/$ZIP_NAME.sig\" \\"
echo "     --repo $REPO --title \"v$VERSION\" --notes \"…\""
echo ""
echo "2) Mettre à jour le tap (repo eliorpom-cmd/homebrew-tap) :"
echo ""
echo "   cp \"$DIST/downloader.rb\" <clone-du-tap>/Casks/downloader.rb"
echo "   # puis commit + push"
echo ""
echo "ℹ️  Les deux fichiers ZIP et .sig doivent être attachés à la release :"
echo "    sans le .sig, les apps installées refuseront la mise à jour."
