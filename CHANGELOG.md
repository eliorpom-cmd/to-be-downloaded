# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and
this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

No version has been published yet. Everything below is what `0.1.0` will contain.

### Added

- **Downloads**: MP4 video or audio (M4A remuxed without re-encoding, MP3 as a
  fallback), quality selection, optional burned-in subtitles, configurable
  filename templates.
- **Queue** with two concurrent downloads by default; oldest job starts first.
- **Playlists**: a playlist link opens a picker (all, a selection, or the single
  targeted video). `RD…` mixes are excluded — they have no stable content.
- **Library**: persistent history at `Application Support/TBD/library.json`,
  thumbnails, duplicate detection by video id, "Download Again", reveal in
  Finder.
- **Resume** of interrupted downloads — partial files survive quitting the app
  and restart from the current byte.
- **LAN server** (FlyingFox) with a web UI, a JSON API, streamed file retrieval,
  PWA install on iOS, and a QR code in the app to reach it.
- **Instant metadata**: thumbnail derived from the URL with no network round
  trip, title from YouTube's oEmbed endpoint (~200 ms) while `yt-dlp` completes
  in the background.
- **macOS integration**: menu bar extra, Dock icon progress, drag a finished file
  to the Finder, Quick Look on the space bar, ⌥⌘V global shortcut, Services entry
  "Download with TBD", `tbd://` URL scheme, clickable completion notifications.
- **Self-updating** app (Ed25519-signed GitHub releases) and yt-dlp (stable or
  nightly channel), both on by default and throttled to once a day.
- **FFmpeg installed on first launch** instead of being bundled: verified
  against its published SHA-256 **and** against an Apple Developer ID signature
  pinned to its publisher's team, then run once before being installed. Takes
  the app from 125 MB to 43 MB, and means nothing this project distributes
  contains FFmpeg — the build previously bundled was compiled `--enable-nonfree`
  and could not legally be redistributed by anyone. See
  [docs/THIRD-PARTY.md](docs/THIRD-PARTY.md#ffmpeg-is-downloaded-not-bundled).
- **Settings**: output directory, default format and quality, port, appearance,
  filename template, update channels, shortcut recorder, About section.
- Monochrome UI in light and dark, sidebar navigation, download rows whose
  background fills with progress.
- **Icon Composer app icon** ([`App/Resources/AppIcon.icon`](App/Resources/AppIcon.icon)):
  a download arrow and two eyes hollowed out of the tile, which `actool` renders
  as Liquid Glass on macOS 26 and as flat bitmaps below. The same drawing is the
  menu bar glyph, the logo on the web UI, and the favicon it serves.

### Fixed

- **Subprocess deadlock**: pipes are now drained while the process runs. Reading
  them only after termination hung yt-dlp past the 64 KB pipe buffer — a playlist
  extraction could never finish.
- **Progress bar filling and emptying**: replaced yt-dlp's per-stream reporting
  with a single monotonic bar covering video, audio and muxing.
- **Videos that wouldn't play**: YouTube serves AV1, which QuickTime can't decode
  on most Macs. Format selection now filters for H.264/AAC in the selector
  itself, not only in `-S`.
- **TLS interception** (parental controls, antivirus, corporate proxies): a trust
  bundle combining Mozilla roots and the system keychain, honored through
  yt-dlp's curl_cffi backend.
- **Stale app in Spotlight**: `install.sh` unregisters every copy other than
  `/Applications` and removes build products that Xcode registered itself.
- **Stuck Dock icon**: install replaces the bundle with a new inode instead of
  copying over it, so Launch Services' icon cache is forced to refresh.
- **Jittery ETA**: quantized countdown with monospaced digits and reserved width,
  so the row stops shifting on every frame.
- **Appearance stuck after switching back to "System"**: `.preferredColorScheme(nil)`
  is not enough; `NSApp.appearance` must be reset too.
- **Underscores in filenames**: `--restrict-filenames` removed.

### Known issues

- The first launch needs a network connection to fetch FFmpeg; there is no
  offline first run.
- The **Share extension** is built and embedded but stays inactive: PlugInKit
  does not register ad-hoc signed extensions. The Services menu covers the same
  need.
- **Apple Silicon only**; no Intel build.
- 4K downloads are VP9 (YouTube has no H.264 above 1080p) and need a player like
  IINA or VLC.

[Unreleased]: https://github.com/eliorpom-cmd/to-be-downloaded/commits/main
