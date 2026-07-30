# Building

## Requirements

- macOS 13+ on **Apple Silicon** (arm64).
- Xcode (command line tools alone are not enough — `xcodebuild` needs the IDE).
- [XcodeGen](https://github.com/yonsson/XcodeGen): `brew install xcodegen`.

`TBD.xcodeproj` is generated and git-ignored. **`project.yml` is the source of
truth.** Run `xcodegen generate` after adding or removing any Swift file,
otherwise the build fails with "cannot find X in scope".

## Build a distributable app

```bash
./scripts/build.sh
```

Produces:

- `dist/TBD.app` — the application,
- `dist/TBD.dmg` — the disk image (volume named "TBD - To be downloaded").

Signing is **ad-hoc** (`codesign -s -`): free, no Apple Developer account, not
notarized. The script signs **inside out** — the bundled binaries first, then the
`.appex`, then the app. Signing the app seals the contents of `PlugIns/`, so
signing the extension afterwards would invalidate the app's signature.

`App/Resources/bin/` holds only `yt-dlp` and `cacert.pem`. **FFmpeg is not in
the repository and must not be added back**: the build that used to live there
was not redistributable, and the app now fetches it on first launch
([THIRD-PARTY.md](THIRD-PARTY.md#ffmpeg-is-downloaded-not-bundled)). A build of
the app therefore has no FFmpeg until you launch it once with a network
connection.

## Install the working copy on this Mac

```bash
./scripts/install.sh
```

Build, then replace `/Applications/TBD - To be downloaded.app`. This is **the**
command to run after changing code if you want to actually use the app.

It also quits a running instance first, and unregisters every copy of the app
other than the one in `/Applications` — see
[TROUBLESHOOTING.md](TROUBLESHOOTING.md#spotlight-keeps-offering-an-old-version)
for why that matters, and for the two rules the script encodes (always
`rm` + `ditto`, never `cp` over an existing bundle; a running app is not updated
by replacing its bundle).

## Refresh the bundled yt-dlp

The app updates yt-dlp by itself on users' machines ([UPDATES.md](UPDATES.md)).
This script exists only so releases don't ship a six-month-old seed:

```bash
./scripts/update-ytdlp.sh [stable|nightly]   # verifies the published SHA-256
./scripts/build.sh
```

`scripts/release.sh` runs it for you.

## The app icon

[`App/Resources/AppIcon.icon`](../App/Resources/AppIcon.icon) is an Icon Composer
package — the single source of the app's identity. There is no generation step:
`actool` compiles it during the build into `Assets.car` (Liquid Glass on macOS 26)
*and* a fallback `AppIcon.icns` for earlier versions. Edit it in Icon Composer,
or edit `Assets/mascot.svg` directly.

Two Swift paths in [`App/Sources/Mascot.swift`](../App/Sources/Mascot.swift) are
transcribed from that same SVG, for the places the bundle icon can't reach:

- `MascotShape` — the mascot alone (arrow + eyes), for the menu bar glyph, the
  in-app views and the logo on the web UI.
- `AppIconShape` — the full tile with the mascot hollowed out, for the PWA icon
  and favicon served over the LAN.

Change the SVG and both need re-transcribing by hand; nothing checks that they
still agree.

## Gotchas

- **`.menuStyle(.borderlessButton)` ignores label decorations** (background,
  border, custom chevron) and adds its own indicator. For a macOS popup button,
  use `Picker` + `.labelsHidden()` + `.fixedSize()`.
- **A `static` method on a `View` is main-actor isolated.** URL validation lives
  in [`Core/YouTubeLink.swift`](../App/Sources/Core/YouTubeLink.swift)
  (nonisolated) so `onDrop` callbacks can call it.
- **`FileManager.url(for: .applicationSupportDirectory)` ignores `$HOME`.** Code
  that touches Application Support cannot be tested against a fake home
  directory — it will hit the real one.
- **TCC prompt when the bundle lives under `~/Documents`.** Launching a build
  from there triggers "wants to access your Documents", which *blocks* window
  interaction (no AppleScript driving, no screenshots) and reappears on every
  launch until answered. Users installing via Homebrew into `/Applications`
  never see it.
