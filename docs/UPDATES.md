# Self-updating

Three independent mechanisms, all **on by default**, configurable in
**Settings → Application** and **Settings → Engine**.

| | What | Where it lands | Rhythm |
| --- | --- | --- | --- |
| **App** | GitHub releases of this repo | replaces its own bundle | once a day |
| **yt-dlp** | releases of the yt-dlp project | `~/Library/Application Support/TBD/bin` | once a day |
| **FFmpeg** | releases from its publisher | same directory | installed on first launch, checked once a day |

Checks run at launch, then hourly while the app is open. Each updater carries its
own 24 h throttle, so the hourly wake-up is almost always a no-op.

An app update installs to disk without interrupting anything: it takes effect at
the next launch, or immediately via the **Relaunch** button.

## Why yt-dlp updates itself

YouTube changes its anti-bot measures constantly and yt-dlp ships fixes just as
often. A binary frozen inside the `.app` goes stale on its own — so yt-dlp
updates **periodically**, not only after a failure. The "Update" banner that
appears after certain errors is just a shortcut.

**Two copies, on purpose.** The yt-dlp in `App/Resources/bin` is only a *seed*
so the app works offline the moment it is installed. The copy actually executed
lives in `~/Library/Application Support/TBD/bin/yt-dlp` and is hot-swappable.
Writing into the bundle instead would invalidate the app's signature, and
`/Applications` is not always writable.
[`BinaryLocator.effectiveYtDlp()`](../App/Sources/Core/BinaryLocator.swift)
resolves managed-copy-first.

Replacing the binary **during** a download is safe: POSIX keeps the running
process on its old inode.

Two channels ([`EngineUpdater.swift`](../App/Sources/Core/EngineUpdater.swift)):
`stable` (`yt-dlp/yt-dlp`) and `nightly` (`yt-dlp/yt-dlp-nightly-builds`, which
gets YouTube fixes same-day). Switching channels forces a reinstall — otherwise
going nightly → stable would be refused as a downgrade. Versions compare
component by component as integers (`2026.07.23.234303` > `2026.07.04`; a
lexicographic compare gets `2026.7.4` wrong).

Only the official `yt-dlp_macos` asset is accepted, its SHA-256 is checked
against the release's sums file, and the binary must answer `--version` before it
replaces the previous one. The replacement is atomic
(`FileManager.replaceItemAt`).

## Why FFmpeg installs itself on first launch

It is not bundled at all — the static build this project used to ship was
compiled `--enable-nonfree` and therefore could not legally be redistributed by
anyone. [THIRD-PARTY.md](THIRD-PARTY.md#ffmpeg-is-downloaded-not-bundled) has
the reasoning; the practical consequence is that the app fetches it once, ~56 MB,
before the first download can run, and shows the progress on the home screen.

This is the **only** download the app starts on its own without being asked.
The justification is narrow: without FFmpeg, nothing the app does can succeed,
so an app that waited to be asked would just be an app that doesn't work.

Checks, in order ([`FFmpegInstaller.swift`](../App/Sources/Core/FFmpegInstaller.swift)):
HTTPS on the expected host → published SHA-256 → **Apple Developer ID signature
pinned to the publisher's team** → the binary must run once → atomic install.
The signature is the real boundary; the checksum, coming from the same host as
the archive, only catches a truncated transfer.

Version checks cost one redirect request — the "latest" URL answers `307` with a
versioned path — so the daily check downloads nothing unless the published
version actually changed. FFmpeg ships a few releases a year, so it usually
does nothing at all.

## Security model of the app updater

The app is **not notarized**, so macOS guarantees nothing about what the updater
downloads. The guarantee comes from an **Ed25519** signature whose public keys
are compiled into the binary (`AppConfig.updatePublicKeys`) and whose private
keys never leave the developer's machine (`~/.config/tbd-release/`, mode `0600`,
outside the repo).

There are **two** keys, and a signature valid for either one is accepted: the
current key, and a backup key stored elsewhere. Without that second set, losing
the current key would kill auto-update forever — fixing the key would require an
update, which is precisely what would no longer work. The trade-off is real (two
keys can authorize an update), hence the rule: **the backup key does not live on
the build machine.**

Concretely, in [`AppUpdater.swift`](../App/Sources/Core/AppUpdater.swift):

1. **Signature required.** An archive not signed by one of those keys is never
   installed. A compromised GitHub repo, a hostile mirror or a TLS interceptor
   cannot forge one.
2. **Verified before extraction.** The decompressor never sees unauthenticated
   data. The archive is read memory-mapped, so verifying 80 MB doesn't mean
   holding 80 MB in RAM.
3. **Nothing from the release is executed.** No install script, no post-install,
   no shell: `/usr/bin/ditto` with an argument array, then a directory
   replacement. `ditto` specifically, because `unzip` destroys permissions,
   extended attributes and the ad-hoc signature.
4. **Constrained contents.** Exactly one `.app`, same `CFBundleIdentifier` as the
   running app, `CFBundleShortVersionString` equal to the release tag, executable
   present. The `Info.plist` is read with `PropertyListSerialization` — never
   `Bundle(url:)`, which would load code. Anything else is refused.
5. **No privilege escalation, ever.** If the app's directory isn't writable, the
   update stops and says so. No admin password prompt, no installing elsewhere.
6. **HTTPS and GitHub hosts only** (`AppConfig.isTrustedUpdateURL`), including
   for URLs that came out of the API response.
7. **Disabled for development builds** — a bundle under `DerivedData` or
   `Build/Products` never auto-updates, so running a local build can't overwrite
   the binary you're testing with.

Replacing the running bundle is safe: POSIX keeps the old inode mapped, so the
app keeps running its old code until relaunch. Relaunch is `server.stop()`, then
`/usr/bin/open -n`, then `NSApp.terminate` — without the stop, the new instance
would find port 8787 already taken.

## Why not Sparkle

A home-grown updater (~350 lines) with CryptoKit's Ed25519 was chosen over
[Sparkle](https://sparkle-project.org): an auditable surface, no embedded
framework, consistent with the size of the project. Sparkle remains the
alternative if delta updates ever matter.

## Independent escape hatch

Homebrew. `brew upgrade --cask to-be-downloaded` verifies the cask's `sha256`
and doesn't involve the signing keys at all. The keys are a single point of
failure for in-app updates only — never for the ability to ship a version.
