# TBD — To be downloaded

App macOS native (SwiftUI) qui télécharge des vidéos/audios via **yt-dlp** et
expose un petit **serveur HTTP local** pour piloter les téléchargements depuis
n'importe quel appareil du réseau (téléphone, tablette…) via une page web —
sans rien installer sur ces appareils.

> Outil personnel, distribué hors App Store.

Le nom a trois formes, chacune pour une largeur d'affichage :

| Forme | Où | Porté par |
| --- | --- | --- |
| `TBD` | barre des menus, menu Partager, Terminal, produit de build `TBD.app` | `PRODUCT_NAME`, `AppConfig.shortName` |
| `To be downloaded` | menu de l'app à côté de la pomme, interface | `CFBundleName`, `AppConfig.displayName` |
| `TBD - To be downloaded` | Finder, Spotlight, Réglages → Application | **nom du bundle installé**, `CFBundleDisplayName`, `AppConfig.fullName` |

**Le bundle ne porte pas le même nom selon qu'il est construit ou installé**, et
c'est délibéré : le build produit `TBD.app` (chemins courts dans le dépôt, les
scripts et le Terminal), mais il s'installe en
`/Applications/TBD - To be downloaded.app`. Raison : **Spotlight indexe une app
par son nom de FICHIER et ignore `CFBundleDisplayName`** — installée sous
`TBD.app`, l'app resterait introuvable en cherchant « to be downloaded »
(vérifié : `mdls` renvoie alors `kMDItemDisplayName = "TBD"`).

Renommer le dossier d'un bundle est sans conséquence : la signature couvre le
contenu, pas le nom, et l'exécutable reste `Contents/MacOS/TBD`. La mise à jour
automatique passe par `FileManager.replaceItemAt`, qui conserve le nom de la
destination — le nom installé survit donc aux mises à jour, et `install.sh`
comme le cask Homebrew (`app "TBD.app", target: "TBD - To be downloaded.app"`)
installent tous deux sous ce nom.

## Fonctionnalités

- Téléchargement **MP4 (vidéo)** ou **audio** (M4A sans ré-encodage, ou MP3)
  avec choix de qualité, et **sous-titres** incrustés en option.
- Une seule **barre de progression monotone**, de l'ouverture du flux à la fin
  de l'assemblage.
- **File d'attente** : deux téléchargements de front par défaut, les autres
  attendent leur tour.
- **Playlists** : un lien de playlist ouvre le choix des vidéos à prendre.
- **Poids estimé** avant de lancer, et détection de ce qui est **déjà dans la
  bibliothèque**.
- **Reprise** des téléchargements interrompus par une fermeture de l'app.
- **Serveur LAN** : ouvre l'UI web depuis un autre appareil, lance un
  téléchargement, puis récupère le fichier fini.
- **QR code** dans l'app pour ouvrir l'UI web d'un scan.
- Gestes macOS : glisser un fichier vers le Finder, **Quick Look** à la barre
  d'espace, progression sur l'icône du Dock, raccourci global ⌥⌘V, entrée
  **Services** « Download with … » depuis n'importe quelle app.
- yt-dlp + ffmpeg **embarqués** dans l'app (rien à installer).

## Prérequis

- macOS 13+ sur **Apple Silicon** (arm64).
- Pour (re)construire : [XcodeGen](https://github.com/yonsson/XcodeGen)
  (`brew install xcodegen`) et Xcode.

## Construire

```bash
./scripts/build.sh
```

Produit :
- `dist/TBD.app` — l'application,
- `dist/TBD.dmg` — l'image disque distribuable (volume « TBD - To be downloaded »).

L'app est signée en **ad-hoc** (gratuit, sans compte Apple Developer).

## Installer la version des sources sur ce Mac

```bash
./scripts/install.sh
```

Construit, puis remplace `/Applications/TBD.app`. C'est **la** commande à lancer
après avoir modifié le code, si tu veux utiliser l'app pour de vrai.

### Pourquoi Spotlight propose parfois une vieille version

Deux registres distincts, et c'est la clé du malentendu :

- **Launch Services** décide qui ouvre quoi (schéma `tbd://`, menu « Ouvrir
  avec », menu Services). On y ajoute et retire des entrées avec `lsregister`.
- **Spotlight** indexe le **système de fichiers**. Un bundle désinscrit de
  Launch Services mais toujours présent sur le disque **ressort quand même**
  dans la recherche. Le seul remède est qu'il n'existe plus.


macOS n'a pas de base des « logiciels installés » : une app est un dossier, la
copier suffit à l'installer. Mais **Launch Services** référence toutes les `.app`
qu'il a croisées, où qu'elles soient — et Xcode y inscrit lui-même chaque
compilation (phase `RegisterWithLaunchServices`, visible dans le log de build).
Chaque `xcodebuild` laisse donc une entrée de plus, dans `build/` ou dans
`~/Library/Developer/Xcode/DerivedData/`. Ces copies ne périment jamais : ce
sont des apps complètes qui se lancent très bien, avec leur code d'alors.

`install.sh` s'en occupe : il désinscrit **toute copie autre que celle de
`/Applications`** — bundles disparus comme produits de build encore présents,
que la compilation vient elle-même d'enregistrer. La purge a lieu *après* le
build, pas avant : au sortir du script, Spotlight ne connaît qu'une seule copie
de l'app. Pour repartir de zéro à la main :

```bash
rm -r build                       # produits de build (regénérables)
"/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/\
LaunchServices.framework/Versions/A/Support/lsregister" -u <chemin.app>
```

Note : `lsregister -kill` (qu'on trouve dans les vieux tutoriels) **n'existe
plus** sur macOS récent — la désinscription se fait chemin par chemin avec `-u`.

Deux détails qui ont chacun coûté une séance de débogage :

- **Toujours supprimer puis `ditto`, jamais un `cp` par-dessus.** Le cache
  d'icônes de Launch Services reste collé à l'ancienne icône tant que le bundle
  garde le même inode. Un dossier neuf le force à relire le `.icns`.
- **Remplacer le bundle d'une app qui tourne ne la met pas à jour.** Le
  processus en vol garde son ancien code mappé en mémoire (POSIX) ; `install.sh`
  quitte donc l'app d'abord.

## Installer / lancer (distribution)

### Via Homebrew (la voie recommandée)

```bash
brew install --cask --no-quarantine eliorpom-cmd/tap/to-be-downloaded
```

`--no-quarantine` est **nécessaire** : l'app est signée en ad-hoc, pas notarisée
par Apple. Sans ce drapeau, macOS met le bundle en quarantaine et refuse de
l'ouvrir. Le drapeau ne désactive rien d'autre, et ne concerne que cette app.

### À la main

Glisse `TBD.app` dans `/Applications`, puis lance-la.

**Premier lancement sur un autre Mac** (l'app n'étant pas notarisée, macOS la
met en quarantaine) :

- **clic droit** sur l'app → **Ouvrir** → **Ouvrir**, ou
- en Terminal : `xattr -dr com.apple.quarantine /Applications/TBD.app`

Sur le Mac qui a servi à la construire, elle se lance directement.

## Mises à jour

Deux mécanismes indépendants, tous deux **activés par défaut** et réglables dans
**Réglages → Application** et **Réglages → Engine** :

| | Quoi | Où | Rythme |
|---|---|---|---|
| **App** | releases GitHub de ce dépôt | remplace le bundle | 1×/jour |
| **yt-dlp** | releases du projet yt-dlp | `~/Library/Application Support/TBD/bin` | 1×/jour |

Le contrôle a lieu au lancement puis toutes les heures tant que l'app tourne
(chaque updater porte son propre intervalle de 24 h, donc le réveil horaire ne
fait presque jamais rien). yt-dlp se met donc à jour **de lui-même,
périodiquement** — pas seulement après un échec ; le bandeau « Update » qui
apparaît après une erreur n'est qu'un raccourci.

Une mise à jour de l'app s'installe sur le disque sans interrompre ce que tu
fais : elle prend effet au prochain lancement, ou tout de suite via le bouton
**Relaunch**.

### Modèle de sécurité

L'app n'est pas notarisée : macOS n'apporte donc **aucune** garantie sur ce que
l'updater télécharge. La garantie vient d'une signature **Ed25519** dont les clés
publiques sont compilées dans le binaire (`AppConfig.updatePublicKeys`) et dont
les clés privées ne quittent jamais la machine du développeur
(`~/.config/tbd-release/`, `0600`, hors du dépôt).

Il y a **deux** clés, et une signature valide pour l'une des deux suffit : la
clé courante, et une clé de secours rangée ailleurs. Sans ce second jeu, perdre
la clé courante condamnerait la mise à jour automatique pour toujours — il
faudrait une mise à jour pour corriger la clé, et c'est précisément ce qui ne
fonctionnerait plus. La contrepartie est réelle (deux clés peuvent autoriser une
mise à jour), d'où la règle : **la clé de secours ne vit pas sur la machine de
build**.

Concrètement, dans [`AppUpdater.swift`](App/Sources/Core/AppUpdater.swift) :

1. **Signature obligatoire.** Une archive non signée par cette clé n'est jamais
   installée. Un dépôt GitHub compromis, un miroir hostile ou un intercepteur
   TLS ne peuvent pas fabriquer de signature valide.
2. **Vérifiée avant extraction.** Le décompresseur ne voit jamais de données non
   authentifiées.
3. **Rien n'est exécuté depuis la release.** Pas de script d'installation, pas
   de post-install, pas de shell : `/usr/bin/ditto` avec des arguments passés en
   tableau, puis un remplacement de dossier. Rien d'autre.
4. **Contenu contraint.** L'archive doit contenir exactement un `.app`, portant
   le même identifiant de bundle que l'app en cours et la version annoncée par
   la release. Tout le reste est refusé.
5. **Aucune élévation de privilèges.** Si le dossier de l'app n'est pas
   inscriptible, la mise à jour s'arrête en le disant. Jamais de demande de mot
   de passe administrateur, jamais d'installation ailleurs.
6. **HTTPS et hôtes GitHub uniquement**, y compris pour les URLs qui viennent de
   la réponse d'API.
7. **Désactivée pour les builds de développement** (chemin sous
   `DerivedData`/`Build/Products`), pour ne jamais écraser un binaire en test.

Pour yt-dlp, même esprit : seul l'asset `yt-dlp_macos` du dépôt officiel est
accepté, son SHA-256 est vérifié contre le fichier de sommes de la release, et
le binaire doit démarrer (`--version`) avant de remplacer le précédent. Le
remplacement est atomique et sans effet sur un téléchargement en cours.

### Publier une version

```bash
./scripts/signing.swift keygen           # clé courante  — une seule fois
./scripts/signing.swift keygen backup    # clé de secours — à ranger AILLEURS
./scripts/release.sh 0.2.0                # build + archive + signature + cask
./scripts/release.sh 0.2.0 backup         # idem, signé avec la clé de secours
```

Le tap Homebrew est un dépôt à part, à créer une seule fois : un repo GitHub
nommé `homebrew-tap` (donc `eliorpom-cmd/homebrew-tap`) contenant
`Casks/to-be-downloaded.rb`. `release.sh` régénère ce fichier à chaque version,
il n'y a plus qu'à le copier et le pousser.

Le script ne publie rien : il prépare `dist/` et affiche la commande
`gh release create` à lancer. Les **deux** fichiers (`.zip` et `.zip.sig`)
doivent être attachés à la release, sinon les apps installées refuseront la mise
à jour. Il refuse aussi de continuer si la clé publique de `AppConfig.swift` ne
correspond plus à ta clé privée — sinon tu publierais une release que personne
ne pourrait installer.

### Si une clé est perdue

1. **Clé courante perdue** → signe la version suivante avec la clé de secours
   (`./scripts/release.sh <version> backup`). Rien ne casse chez personne. Dans
   cette version, remplace la clé courante par une clé neuve dans
   `updatePublicKeys` (sans jamais retirer celles déjà publiées) et regénère une
   nouvelle clé de secours.
2. **Les deux clés perdues** → la mise à jour automatique s'arrête là, mais la
   distribution non : les utilisateurs restent joignables par Homebrew
   (`brew upgrade --cask to-be-downloaded`), qui vérifie le `sha256` du cask. Il
   suffit
   de publier une version portant de nouvelles clés. C'est pénible, pas fatal.

Autrement dit, la clé n'est un point unique de défaillance que pour la mise à
jour *dans l'app* — jamais pour la capacité à livrer une nouvelle version.

### Renommer le dépôt

Tant qu'aucune release n'est publiée, c'est gratuit. Ensuite, deux endroits :
`AppConfig.updateRepository` (ce que l'app interroge) et la commande `brew` du
tap. `release.sh` déduit le dépôt du remote git et **refuse de construire** si
les deux ne concordent pas.

## Utiliser

1. Colle un lien, choisis **Video** ou **Audio** + la qualité, clique la flèche.
   Les fichiers arrivent dans `~/Downloads`.
2. Un lien de **playlist** ouvre une feuille de choix — tout, une sélection, ou
   la seule vidéo visée par le lien.
3. Pour piloter depuis le **téléphone** (même Wi-Fi) : scanne le QR code affiché
   dans l'app, ou ouvre l'adresse `http://<ip-du-mac>:8787`.
   - macOS peut demander d'**autoriser les connexions entrantes** → Autoriser.

## Entrées système

| Chemin | État |
| --- | --- |
| Menu **Services** → « Download with … » | fonctionne |
| Schéma d'URL `tbd://download?url=…` | fonctionne |
| Raccourci global ⌥⌘V | fonctionne (à activer dans les réglages) |
| **Extension de partage** (menu Partager de Safari) | **inactive sans signature Apple** |

L'extension de partage est construite et embarquée dans
`Contents/PlugIns/Share.appex`, mais **PlugInKit refuse de l'enregistrer** tant
que l'app est signée en ad-hoc : `pluginkit -m -A -D` ne la voit pas, là où une
extension signée Developer ID sur la même machine apparaît. Elle s'activera
d'elle-même le jour où l'app sera signée avec un compte développeur Apple ;
d'ici là, le menu **Services** rend le même service depuis n'importe quelle app.

## Rafraîchir le yt-dlp embarqué

L'app met yt-dlp à jour toute seule chez les utilisateurs (voir *Mises à jour*).
Ce script ne sert qu'à ne pas **distribuer** un `.app` dont l'amorce est vieille :

```bash
./scripts/update-ytdlp.sh [stable|nightly]   # vérifie aussi le SHA-256 publié
./scripts/build.sh                           # reconstruit l'app
```

`scripts/release.sh` le lance déjà pour toi.

## Architecture

- `App/Sources/Core/` — moteur : `DownloadEngine` (subprocess yt-dlp sans shell,
  progression via `--progress-template`), `DownloadManager` (file de jobs
  partagée), `TrustStore` (bundle CA système, gère les intercepteurs TLS),
  `BinaryLocator`.
- `App/Sources/Server/` — serveur `FlyingFox` + page web (`WebUI`).
- `App/Sources/Views/` — écrans SwiftUI (Download, Library, Settings, Network).
- `App/Sources/` — coquille de l'app, `QRGenerator`, gestes macOS
  (`DockProgress`, `QuickLook`, `GlobalShortcut`, `AppDelegate`).
- `Extension/Share/` — extension de partage (cf. *Entrées système*).
- `App/Resources/bin/` — binaires embarqués (yt-dlp, ffmpeg, ffprobe, cacert.pem).

## Note technique — certificats SSL

yt-dlp utilise le backend **curl_cffi** (`--impersonate`) qui honore un bundle
CA combinant les racines publiques **et le trousseau système macOS**. Cela
permet de fonctionner même derrière un intercepteur TLS local (contrôle
parental, antivirus, proxy d'entreprise).
