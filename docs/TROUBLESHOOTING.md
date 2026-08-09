# Troubleshooting

## "The app is damaged" / macOS refuses to open it

The app is ad-hoc signed and **not notarized** (notarization requires a paid
Apple Developer account). macOS quarantines anything downloaded and unnotarized.

Whichever way it was installed, this lifts the tag:

```bash
xattr -dr com.apple.quarantine "/Applications/TBD - To be downloaded.app"
```

Homebrew used to do it for you with `--no-quarantine` and dropped the flag in
5.1, so the line is now run by hand — see the [README](../README.md#install).

Without it, the way through is **System Settings → Privacy & Security →
Security → Open Anyway**, after a first refused launch. Control-clicking the app
and choosing **Open** no longer works: Apple removed that shortcut in macOS
Sequoia, and most guides on the web still recommend it.

On the Mac that built it, it opens directly.

## Spotlight keeps offering an old version

Two registries, and confusing them is the whole problem:

- **Launch Services** decides what opens what (the `tbd://` scheme, "Open with",
  the Services menu). Entries are added and removed with `lsregister`.
- **Spotlight** indexes the **file system**. A bundle unregistered from Launch
  Services but still on disk **still shows up**. The only cure is for it to stop
  existing.

macOS has no "installed software" database — an app is a folder, copying it
installs it. But Launch Services references every `.app` it has ever seen,
wherever it lives, and **Xcode registers each build itself** (the
`RegisterWithLaunchServices` phase, visible in the build log). Every `xcodebuild`
therefore leaves one more entry, in `build/` or in
`~/Library/Developer/Xcode/DerivedData/`. Those copies never expire: they are
complete, perfectly launchable apps running whatever code they were built from.

`./scripts/install.sh` handles this — it unregisters **every copy other than the
one in `/Applications`** and deletes the `.app` products left in `build/` and
`dist/` (object files stay in `Intermediates.noindex`, so the next build is still
incremental). The purge happens *after* the build, not before. By hand:

```bash
rm -r build
"/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/\
LaunchServices.framework/Versions/A/Support/lsregister" -u <path.app>
```

`lsregister -kill`, which old tutorials mention, **no longer exists** on current
macOS. Unregistering is path by path with `-u`.

## The Dock icon is the old one / a generic placeholder

Launch Services caches icons **per inode**. Copying a new bundle over an old one
with `cp` keeps the inode and the cache keeps serving the old icon —
`lsregister -f` does not help.

Always **delete then `ditto`**, never `cp` over an existing bundle. That is what
`install.sh` does.

To tell a cache problem from a broken `.icns`: probe
`NSWorkspace.shared.icon(forFile:)` and write the PNG out, and build a minimal
test bundle carrying the same `.icns`. If the test bundle renders the icon and
the app doesn't, it's the cache.

## Replacing the bundle didn't update the running app

It never does. A running process keeps its old code mapped in memory (POSIX).
Quit the app first — `install.sh` does, and the in-app updater relaunches
explicitly for the same reason.

## "unable to get local issuer certificate" / TLS errors

Something on the machine is intercepting HTTPS and re-signing it with a private
root — parental controls (Qustodio does this), antivirus, corporate proxy. The
frozen yt-dlp binary uses `certifi` internally and **ignores `SSL_CERT_FILE`**,
so it doesn't see that root.

TBD's fix: `--impersonate chrome` forces the **curl_cffi** backend bundled inside
yt-dlp, which *does* honor `CURL_CA_BUNDLE`, pointed at a combined bundle of
Mozilla roots plus the system keychain, generated at launch by
[`TrustStore.prepareBundle`](../App/Sources/Core/TrustStore.swift) into
`Application Support/TBD/trust.pem`.

**Do not use `--no-check-certificates`** — it removes the protection instead of
fixing the trust chain.

## "FFmpeg didn't install"

FFmpeg is downloaded on first launch instead of being bundled
([THIRD-PARTY.md](THIRD-PARTY.md#ffmpeg-is-downloaded-not-bundled)). Until it
lands, no download can complete, so the home screen shows the setup step rather
than the URL field. **Try Again** restarts it; the app never installs a half-
verified copy, so a failed attempt leaves nothing behind.

What the message means:

- *checksum mismatch* — the transfer was truncated. Retry.
- *signed by someone else than expected* — the archive did not carry the
  publisher's Apple Developer ID signature. That is the check refusing a
  substituted binary; do not work around it.
- *the FFmpeg server answered 5xx* / timeouts — the publisher's host is down.
  Retry later; nothing else in the app is affected.

Where it ends up: `~/Library/Application Support/TBD/bin/{ffmpeg,ffprobe}`.
Deleting those two files makes the app reinstall them on next launch.

## A downloaded video won't play

QuickTime can't decode **AV1** on most Macs, and YouTube serves AV1 freely. TBD
asks for H.264/AAC explicitly (see
[ARCHITECTURE.md](ARCHITECTURE.md#the-download-engine)), but **YouTube has no
H.264 above 1080p** — a 4K download is VP9 and needs a player like
[IINA](https://iina.io) or VLC.

If the thumbnail is missing too, that's the same cause: AVFoundation can't decode
the frame either, so TBD falls back to the bundled ffmpeg to extract it.

## The Share extension doesn't appear

**An ad-hoc signed app extension is not registered by PlugInKit.** `pluginkit -m -A -D`
doesn't list it, even though Launch Services knows the bundle (`lsregister -dump`
shows it) and a Developer ID–signed extension on the same machine does appear.

It is built and embedded in `Contents/PlugIns/Share.appex`, and it will activate
on its own the day the app is signed with an Apple Developer account. Until then
the **Services** menu ("Download with TBD") does the same job from any app, and
so does the `tbd://download?url=…` scheme.

## The menu bar icon is missing

On Macs with a notch and a crowded menu bar, macOS parks extra items **off
screen** — the `MenuBarExtra` exists at x=-4092 and is simply not visible.
Verifiable through Accessibility (`menu bar 2`). Remove some menu bar items.

## The LAN web UI is unreachable from the phone

- Both devices must be on the **same Wi-Fi**.
- macOS may ask to **allow incoming connections** the first time — allow it.
  If it was denied: System Settings → Network → Firewall → Options.
- The port is configurable in Settings (default 8787); the QR code always encodes
  the current address.

## Settings show a yt-dlp channel I didn't pick

The settings display the channel of the **installed** binary when it differs from
the preference — usually the trace of a manual install or a CLI experiment.
Switching the channel in Settings forces a reinstall and realigns both.
