# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and
this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

Nothing yet.

## [1.1.0] - 2026-08-11

A release made of other people's reports. Two of them are about the app
taking decisions that were never its to take: opening a network port on
someone's machine at launch, and downloading 56 MB onto it without asking.
Both are now questions. The rest is the accumulation of small things people
noticed before they noticed the app.

### Changed

- **The LAN server is opt-in.** Launching the app binds nothing. Turning
  Remote Control on opens the port and remembers the choice; turning it off,
  or quitting, closes it. Requested repeatedly, and the most common single
  complaint about 1.0.
- **Network Access is called Remote Control**, and its screen explains the
  feature instead of showing a dimmed QR code: what the page does, that
  nothing is exposed to the internet, that the port's life is tied to the
  switch, and that anyone on the Wi-Fi with the address can queue a download,
  because there is no password.
- **The app is written "To Be Downloaded"**, with capitals, everywhere it is
  read. The folder in `/Applications` keeps its old lowercase name on
  purpose: it exists on other people's disks, and renaming it would hand
  them two copies of the app.
- **Settings say what they do.** "At the same time" is now "Concurrent
  downloads"; "Default format" is "Download as", since Video and Audio are
  not formats. The Engine section is Components, and it leads with the fact
  that yt-dlp and FFmpeg update themselves rather than with two Check Now
  buttons. Em dashes are out of the copy.
- **"Remove from Library" is "Remove from Library (Keep File)"**, with "Move
  File to Trash…" beside it. Nobody could tell which one their file was
  about to survive.
- Library and Settings no longer print their own name at the top; the sidebar
  already says where you are.

### Added

- **First-launch screens.** Where downloads go, and whether to fetch FFmpeg.
  Nothing is downloaded before you answer. An FFmpeg already on the machine
  (Homebrew, MacPorts, or one you point at) is linked instead of duplicated,
  and the app then leaves its updates to whoever installed it. Upgrades from
  1.0 skip all of this.
- **A preview of the pasted link**, before the download rather than after:
  thumbnail, title, channel, length. Nearly free — the thumbnail address
  comes from the video id in the URL and the title from one oEmbed call — so
  a stale clipboard is caught while it can still be fixed.
- **A warning on Max quality**, once, dismissible. YouTube serves H.264 only
  up to 1080p, so 4K arrives as VP9, and the TV app, QuickTime and Preview
  open it with no picture. Reported as a broken download; the file is fine
  and VLC plays it. Nothing is silently downgraded.
- **Subtitle language and automatic captions** are now settings. The language
  was the system's plus English, in code, with no way to say otherwise.

### Fixed

- **Removing a library entry removes the download it came from.** The two are
  the same thing seen twice, so the row used to stay on the Download screen
  and, since that list is what the LAN server serves, on every phone pointed
  at the Mac.
- **FFmpeg is checked for updates at launch**, not only in the hourly loop. A
  Mac opened and closed inside an hour updated it exactly never, which is why
  people believed it had to be done by hand.
- **The Video/Audio toggle stops sliding sideways** when the quality control
  changes width, in the app and on the web page.
- **The web page stops offering a choice of one**: audio keeps the source
  track, so it prints "Original quality" instead of drawing a dropdown.
- **The favicon has a transparent background** instead of an opaque square.
- **Settings centre on a wide window**, and their scroll bar sits on the
  window edge rather than against the content.
- **The focus ring is gone from the URL field.** The caret already says where
  the keyboard goes, and the ring was what made the round button look
  crooked — the arrow was measurably centred all along.
- **The About panel is in English** and carries the copyright and licence,
  instead of the words "Outil personnel".

### Removed

- **"New Window"**, and with it ⌘N and the tab bar macOS folds two windows
  into. A second window showed the same single queue.
- **⌘L and ⌘⇧V.** The field is already focused when the window opens, and
  ⌘V then Return is the same number of keys. The system-wide ⌥⌘V in Settings
  is untouched.

## [1.0.0] - 2026-08-08

The first public release. The repository is open, and this is a normal release
rather than a pre-release — which is the thing the updater was waiting for.
Every app installed from here on asks GitHub for releases once a day, checks
the Ed25519 signature, and updates itself. Beta builds never could: a private
repository answers 404, and the updater ignores pre-releases by design.

What the app does has not changed since 0.1.0. What changed is everything
around it — the licence on every file, the documentation a stranger reads
first, and the fact that there is now source to read at all.

### Added

- **Homebrew cask**, in the public tap `eliorpom-cmd/homebrew-tap`:
  `brew install --cask eliorpom-cmd/tap/to-be-downloaded`, followed by an
  `xattr -dr com.apple.quarantine` on the installed app. Homebrew dropped
  `--no-quarantine` in 5.1 — it refuses the option outright — so lifting the
  quarantine is now something the person installing does knowingly rather than
  something a package manager does for them. `TBD.dmg` is attached to the
  release for anyone who would rather not open a terminal at all.
- **Continuous integration** on every push: the project builds from
  `project.yml` with warnings as errors, and the scripts are shellchecked.
- **A source offer on the web UI.** The LAN server hands the app to a browser,
  which under AGPL §13 means it has to hand over where the source lives too.
- **[docs/GOING-PUBLIC.md](docs/GOING-PUBLIC.md)**, which records what had to be
  true before the repository could be published — including the history rewrite
  that removed the nonfree FFmpeg binaries from all 19 commits.

### Changed

- **Warnings are errors** in the build settings, rather than a promise in a
  contributing guide.
- **An AGPL-3.0 header on every source file**, so a file read on its own still
  says what it is licensed under.
- Nothing in the repository points at the machine it was built on any more.

## [0.1.0] - 2026-07-31

First build handed to beta testers. Private beta: the repository is not public
and the release is marked as a pre-release, so no installed app picks it up on
its own.

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

[Unreleased]: https://github.com/eliorpom-cmd/to-be-downloaded/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/eliorpom-cmd/to-be-downloaded/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/eliorpom-cmd/to-be-downloaded/compare/v0.1.0...v1.0.0
[0.1.0]: https://github.com/eliorpom-cmd/to-be-downloaded/releases/tag/v0.1.0
