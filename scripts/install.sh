#!/usr/bin/env bash
#
# Installe la version courante des sources dans /Applications.
#
# Usage :  ./scripts/install.sh
#
# À savoir sur macOS : il n'existe pas de base des « logiciels installés ». Une
# app est un simple dossier, et Launch Services référence TOUTES les copies
# qu'il a croisées — y compris celles que xcodebuild dépose dans build/ et que
# Xcode enregistre lui-même à chaque compilation. C'est ainsi qu'on se retrouve
# avec de vieilles versions dans Spotlight, parfaitement fonctionnelles et
# parfaitement périmées.
#
# Ce script tranche : /Applications est la SEULE copie installée, tout le reste
# est du produit de build jetable, désinscrit et supprimé au passage.
#
set -euo pipefail

# Nom du produit de build : court et sans espace, c'est lui qu'on manipule dans
# le dépôt, les scripts et le Terminal.
APP_NAME="TBD"
# Nom du bundle UNE FOIS INSTALLÉ. Différent exprès : Spotlight indexe une app
# par son NOM DE FICHIER et ignore CFBundleDisplayName — installée sous « TBD »,
# l'app resterait introuvable en cherchant « to be downloaded ».
# Renommer le dossier d'un bundle est sans effet sur sa signature (elle couvre
# le contenu) et sur l'exécutable (CFBundleExecutable reste « TBD »).
INSTALLED_NAME="TBD - To be downloaded"
BUNDLE_ID="com.byelior.tbd"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="/Applications/$INSTALLED_NAME.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"

cd "$ROOT"

# Remplacer le bundle d'une app qui tourne ne la met pas à jour : le processus
# en vol garde son ancien code mappé en mémoire (POSIX). Autant la quitter.
if /usr/bin/pgrep -x "$APP_NAME" >/dev/null 2>&1; then
  echo "▶ $APP_NAME tourne — fermeture…"
  /usr/bin/osascript -e "quit app id \"$BUNDLE_ID\"" 2>/dev/null || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    /usr/bin/pgrep -x "$APP_NAME" >/dev/null 2>&1 || break
    /bin/sleep 0.5
  done
fi

"$ROOT/scripts/build.sh"

SOURCE="$ROOT/dist/$APP_NAME.app"
[ -d "$SOURCE" ] || { echo "❌ Introuvable après build : $SOURCE"; exit 1; }

# Accolades obligatoires : collé à « … », bash avale les octets UTF-8 dans le
# nom de la variable.
echo "▶ Installation dans ${TARGET}…"
# Supprimer puis ditto, et surtout pas un cp par-dessus : le cache d'icônes de
# Launch Services reste collé à l'ancienne icône tant que le bundle garde le
# même inode. Un dossier neuf le force à relire le .icns.
rm -rf "$TARGET"
/usr/bin/ditto "$SOURCE" "$TARGET"

echo "▶ Enregistrement auprès de Launch Services…"
"$LSREGISTER" -f "$TARGET"

# Désinscription de TOUTE copie autre que celle de /Applications : les bundles
# disparus (anciens produits de build) comme ceux encore présents dans build/ et
# dist/, que la compilation vient elle-même d'enregistrer. Ils reviendront au
# prochain build — d'où la purge ICI, après, plutôt qu'avant : au sortir de ce
# script, Spotlight ne connaît qu'une seule copie de l'app.
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

# Spotlight n'interroge PAS le registre de Launch Services : il indexe le
# système de fichiers. Un bundle désinscrit mais toujours sur le disque ressort
# donc quand même dans la recherche. Le seul remède est qu'il n'existe plus.
#
# On ne retire que les .app produites, pas les dossiers de build qui les
# entourent : les objets compilés vivent dans Intermediates.noindex, la
# prochaine compilation reste incrémentale (elle réédite les liens, sans tout
# recompiler). Le DMG est conservé, Spotlight n'indexe pas l'intérieur d'une
# image disque non montée.
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
echo "✅ $INSTALLED_NAME $VERSION installée dans /Applications"
[ "$PURGED" -gt 0 ] && echo "   ($PURGED copie(s) parallèle(s) désinscrite(s) de Launch Services)"
echo ""
echo "ℹ️  Copies de l'app présentes sur le disque :"
/usr/bin/mdfind "kMDItemKind == 'Application'" 2>/dev/null \
  | /usr/bin/grep -E "/($APP_NAME|$INSTALLED_NAME)\.app$" | sort -u \
  | /usr/bin/sed 's/^/    /'
