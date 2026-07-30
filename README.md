# TBD — To be downloaded

A native macOS app (SwiftUI) that downloads video and audio with **yt-dlp**, and
serves a small **local web UI** so you can start downloads from any device on
the same Wi-Fi — phone, tablet, another laptop — without installing anything on
them.

macOS 13+ · Apple Silicon · not sandboxed · distributed outside the App Store.

> **Status:** pre-release (`0.1.0`). No GitHub release has been published yet.

---

## Features

- **MP4 video** or **audio** (M4A remuxed without re-encoding, MP3 as a
  fallback), with quality selection and optional burned-in subtitles.
- A single **monotonic progress bar** covering the whole job — video stream,
  audio stream, and muxing — instead of yt-dlp's per-stream 0→100 cycles.
- **Queue**: two concurrent downloads by default, the rest wait their turn.
- **Playlists**: a playlist link opens a picker (all, a selection, or just the
  one video the link points at).
- **Estimated size** before starting, and detection of what is **already in
  your library**.
- **Resume** of downloads interrupted by quitting the app.
- **LAN server**: open the web UI from another device, start a download, then
  pull the finished file.
- **QR code** in the app to open that web UI by scanning.
- macOS integration: drag a finished file to the Finder, **Quick Look** with the
  space bar, Dock icon progress, the ⌥⌘V global shortcut, and a **Services**
  entry ("Download with TBD") available from any app.
- yt-dlp is **bundled**; FFmpeg is fetched once on first launch (see
  [First launch](#first-launch)). Nothing to install by hand either way.
- **Self-updating**: the app, yt-dlp and FFmpeg each check for updates once a
  day.

## Install

### Homebrew (recommended, once a release exists)

```bash
brew install --cask --no-quarantine eliorpom-cmd/tap/to-be-downloaded
```

`--no-quarantine` is **required**. The app is ad-hoc signed, not notarized by
Apple (notarization needs a paid Apple Developer account). Without the flag,
macOS quarantines the bundle and refuses to open it. The flag affects this app
only and disables nothing else.

### Manually

Drag `TBD.app` into `/Applications` and launch it. On a Mac other than the one
that built it, the first launch needs one of:

- **right-click** the app → **Open** → **Open**, or
- `xattr -dr com.apple.quarantine "/Applications/TBD - To be downloaded.app"`

### From source

```bash
brew install xcodegen
./scripts/install.sh     # build + install into /Applications
```

See [docs/BUILDING.md](docs/BUILDING.md) for the full build story.

## First launch

The app downloads **FFmpeg** once (~56 MB) before the first download can run,
and says so on screen while it does. It comes from
[ffmpeg.martin-riedl.de](https://ffmpeg.martin-riedl.de), is checked against the
published SHA-256, and must carry a valid Apple **Developer ID** signature from
that publisher — otherwise it is thrown away rather than installed.

Why it isn't simply bundled: the static build this project used to ship was
compiled `--enable-nonfree`, which makes it **not legally redistributable** by
anyone, under any license. Fetching it from the party who *is* allowed to
distribute it fixes that, and takes the app from 125 MB to 43 MB.
[docs/THIRD-PARTY.md](docs/THIRD-PARTY.md#ffmpeg-is-downloaded-not-bundled)
has the full reasoning.

## Usage

1. Paste a link, pick **Video** or **Audio** plus a quality, click the arrow.
   Files land in `~/Downloads`.
2. A **playlist** link opens a sheet: take everything, a selection, or only the
   video the link targeted.
3. To drive it **from your phone** (same Wi-Fi): scan the QR code shown in the
   app, or open `http://<mac-ip>:8787`.
   - macOS may ask to **allow incoming connections** → Allow.

## Documentation

| Document | What's in it |
| --- | --- |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Layout, the download engine, the LAN server, the naming scheme |
| [docs/BUILDING.md](docs/BUILDING.md) | Building, installing from source, refreshing the bundled yt-dlp |
| [docs/UPDATES.md](docs/UPDATES.md) | How the app and yt-dlp update themselves, and the security model behind it |
| [docs/RELEASING.md](docs/RELEASING.md) | Cutting a release, signing keys, the Homebrew tap, key loss |
| [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | Stale Spotlight results, quarantine, TLS interception, inactive Share extension |
| [docs/THIRD-PARTY.md](docs/THIRD-PARTY.md) | Bundled and downloaded components, their licenses, and why FFmpeg is not shipped |
| [CONTRIBUTING.md](CONTRIBUTING.md) | How to propose a change |
| [SECURITY.md](SECURITY.md) | Reporting a vulnerability |
| [CHANGELOG.md](CHANGELOG.md) | Notable changes per version |

## Legal

TBD is a front-end for yt-dlp. It downloads what you point it at; what you are
allowed to point it at is between you, the site's terms of service, and your
local copyright law. Downloading material you do not have the right to copy is
your responsibility, not the app's.

## License

[MIT](LICENSE) for this project's own source. Bundled third-party components
keep their own licenses — see [docs/THIRD-PARTY.md](docs/THIRD-PARTY.md).

## Credits

Built by [Elior Pommier](https://byelior.com). Standing on
[yt-dlp](https://github.com/yt-dlp/yt-dlp), [FFmpeg](https://ffmpeg.org) and
[FlyingFox](https://github.com/swhitty/FlyingFox).

If it saves you time, [buy me a coffee](https://ko-fi.com/eliorpom).
