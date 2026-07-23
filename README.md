# Downloader

App macOS native (SwiftUI) qui télécharge des vidéos/audios via **yt-dlp** et
expose un petit **serveur HTTP local** pour piloter les téléchargements depuis
n'importe quel appareil du réseau (téléphone, tablette…) via une page web —
sans rien installer sur ces appareils.

> Outil personnel, distribué hors App Store. Le nom « Downloader » est un
> placeholder (voir *Renommer* plus bas).

## Fonctionnalités

- Téléchargement **MP4 (vidéo)** ou **MP3 (audio)** avec choix de qualité.
- Progression en temps réel (vitesse, ETA).
- **Serveur LAN** : ouvre l'UI web depuis un autre appareil, lance un
  téléchargement, puis récupère le fichier fini.
- **QR code** dans l'app pour ouvrir l'UI web d'un scan.
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
- `dist/Downloader.app` — l'application,
- `dist/Downloader.dmg` — l'image disque distribuable.

L'app est signée en **ad-hoc** (gratuit, sans compte Apple Developer).

## Installer / lancer

Glisse `Downloader.app` dans `/Applications`, puis lance-la.

**Premier lancement sur un autre Mac** (l'app n'étant pas notarisée, macOS la
met en quarantaine) :

- **clic droit** sur l'app → **Ouvrir** → **Ouvrir**, ou
- en Terminal : `xattr -dr com.apple.quarantine /Applications/Downloader.app`

Sur le Mac qui a servi à la construire, elle se lance directement.

## Utiliser

1. Colle un lien, choisis **Vidéo MP4** ou **Audio MP3** + la qualité, clique
   **Télécharger**. Les fichiers arrivent dans `~/Downloads/Downloader/`.
2. Pour piloter depuis le **téléphone** (même Wi-Fi) : scanne le QR code affiché
   dans l'app, ou ouvre l'adresse `http://<ip-du-mac>:8787`.
   - macOS peut demander d'**autoriser les connexions entrantes** → Autoriser.

## Mettre à jour yt-dlp

YouTube change souvent ; si les téléchargements échouent :

```bash
./scripts/update-ytdlp.sh   # récupère la dernière version de yt-dlp
./scripts/build.sh          # reconstruit l'app
```

## Renommer l'app

Le nom vit à deux endroits :
- `project.yml` : `name`, `PRODUCT_NAME`, `INFOPLIST_KEY_CFBundleDisplayName`
  (puis relancer `xcodegen generate`),
- `App/Sources/AppConfig.swift` : `displayName` (nom affiché dans l'UI).

## Architecture

- `App/Sources/Core/` — moteur : `DownloadEngine` (subprocess yt-dlp sans shell,
  progression via `--progress-template`), `DownloadManager` (file de jobs
  partagée), `TrustStore` (bundle CA système, gère les intercepteurs TLS),
  `BinaryLocator`.
- `App/Sources/Server/` — serveur `FlyingFox` + page web (`WebUI`).
- `App/Sources/` — UI SwiftUI native + `QRGenerator`.
- `App/Resources/bin/` — binaires embarqués (yt-dlp, ffmpeg, ffprobe, cacert.pem).

## Note technique — certificats SSL

yt-dlp utilise le backend **curl_cffi** (`--impersonate`) qui honore un bundle
CA combinant les racines publiques **et le trousseau système macOS**. Cela
permet de fonctionner même derrière un intercepteur TLS local (contrôle
parental, antivirus, proxy d'entreprise).
