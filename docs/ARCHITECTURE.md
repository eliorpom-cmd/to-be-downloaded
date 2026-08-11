# Architecture

## Layout

```
App/
  Info.plist              URL scheme (tbd://), NSServices, LSUIElement…
  TBD.entitlements
  Resources/bin/          bundled: yt-dlp (seed), cacert.pem — FFmpeg is NOT here
  Sources/
    TBDApp.swift          @main, scenes, MenuBarExtra
    AppConfig.swift       names, bundle paths, update repo + public keys
    AppSettings.swift     UserDefaults-backed preferences (@MainActor singleton)
    RootView.swift        custom sidebar + AppRoute (download/library/network/settings)
    Core/                 the engine — no SwiftUI in here
    Server/               FlyingFox HTTP server + the web UI it serves
    Views/                SwiftUI screens
Extension/Share/          Share-sheet extension (see TROUBLESHOOTING.md)
scripts/                  build, install, release, signing, icon, yt-dlp refresh
project.yml               XcodeGen manifest — the source of truth for the Xcode project
```

`TBD.xcodeproj` is **generated and git-ignored**. Edit `project.yml`, never the
project file. Re-run `xcodegen generate` after adding a Swift file, or the build
fails with "cannot find X in scope".

## The download engine

[`Core/DownloadEngine.swift`](../App/Sources/Core/DownloadEngine.swift) runs
yt-dlp as a subprocess — arguments as an array, **never a shell string**, so
there is no quoting surface to get wrong. The URL is passed after `--`.

Progress comes from `--progress-template 'download:PROG:%(progress)j'` with
`--newline`, parsed as JSON in
[`DownloadProgress.swift`](../App/Sources/Core/DownloadProgress.swift). The final
path is retrieved with `--print-to-file after_move:filepath`.

Three decisions in there are not obvious and are worth keeping:

**Never read a pipe after `waitUntilExit`.**
[`ProcessRunner`](../App/Sources/Core/ProcessRunner.swift) drains both pipes with
`readabilityHandler` while the process runs. Reading them only in
`terminationHandler` deadlocks: past the 64 KB pipe buffer, yt-dlp blocks writing
and never terminates. A playlist extraction (a 425-entry JSON dump) hung for
almost a minute before this was found; `--dump-single-json` for a single video is
already several hundred KB.

**Codec selection is in the format selector, not in `-S`.** YouTube serves AV1,
which QuickTime cannot decode on most Macs. `-S "vcodec:h264"` alone is not
enough — yt-dlp then falls back to a heavier muxed HLS stream. The selector
itself filters:
`bv*[vcodec^=avc1][height<=H]+ba[acodec^=mp4a]/…` with `-S "res:H,ext:mp4:m4a"`.
Above 1080p YouTube has no H.264, so 4K downloads are VP9 and need a player like
IINA.

**One monotonic progress bar.** yt-dlp reports per stream: video 0→100 %, then
audio 0→100 %, then muxing. Shown raw, the bar fills and empties. `%(progress.filename)s`
in the template detects the stream change, and
[`DownloadJob.phaseSpan`](../App/Sources/Core/DownloadJob.swift) weights the
phases (video 0–58 %, audio 58–88 %, muxing 88–100 %; audio-only 0–85 %), with
`max()` so it never goes backwards. Muxing has no progress to report, so it
approaches 100 % asymptotically (`1 - exp(-t/5)`) on a 200 ms ticker.

Other engine pieces:

- [`DownloadManager`](../App/Sources/Core/DownloadManager.swift) — `@MainActor`
  observable job queue (two concurrent by default), retries, external links,
  library writes.
- [`LibraryStore`](../App/Sources/Core/LibraryStore.swift) — JSON at
  `Application Support/TBD/library.json`. Not SwiftData: the deployment target is
  macOS 13.
- [`TrustStore`](../App/Sources/Core/TrustStore.swift) — see *TLS interception*
  in [TROUBLESHOOTING.md](TROUBLESHOOTING.md).
- [`BinaryLocator`](../App/Sources/Core/BinaryLocator.swift) — resolves which
  yt-dlp to run (managed copy first, bundled seed as fallback) and strips the
  quarantine attribute so the bundled binaries start on other Macs. FFmpeg has
  no seed: `effectiveFFmpeg()` throws `notInstalled` until the first-launch
  download lands, which the UI treats as a setup step rather than an error.
- [`FFmpegInstaller`](../App/Sources/Core/FFmpegInstaller.swift) — downloads,
  authenticates and installs FFmpeg, which the app deliberately does not ship
  ([THIRD-PARTY.md](THIRD-PARTY.md#ffmpeg-is-downloaded-not-bundled)).
- [`CodeSignature`](../App/Sources/Core/CodeSignature.swift) — Developer ID
  verification through the Security framework rather than shelling out to
  `codesign`: no subprocess, no output parsing, and a usable error.
- Pause is `Process.suspend()` / `resume()`. Cancelling calls `resume()` **before**
  `terminate()` — a suspended process never handles SIGTERM and would survive.

Partial downloads live in `Application Support/TBD/partials/<jobID>` (not `/tmp`,
which macOS sweeps), are deleted only on success or cancellation, and `pending.json`
lets a relaunch resume the same job id from the byte it stopped at.

## The LAN server

[`Server/ServerController.swift`](../App/Sources/Server/ServerController.swift)
runs [FlyingFox](https://github.com/swhitty/FlyingFox) bound to `.inet(port:)`
— that is `0.0.0.0`, hence reachable from the LAN. `HTTPServer` is an **actor**,
so `appendRoute`/`run`/`stop` are `await`ed.

| Route | Purpose |
| --- | --- |
| `GET /` | the web UI ([`WebUI.swift`](../App/Sources/Server/WebUI.swift), inline HTML/CSS/JS) |
| `GET /api/jobs` | job list as `JobDTO[]` |
| `POST /api/download` | `{url, kind, quality}` |
| `POST /api/cancel/:id`, `POST /api/clear` | queue control |
| `GET /api/metadata?url=` | pre-download preview |
| `GET /api/file/:id` | the finished file, streamed (never loaded into memory) |
| `GET /manifest.webmanifest`, `GET /icon-512.png` | PWA install on iOS |

The server shares the **same `DownloadManager` instance** as the native UI — one
queue, no duplicated logic. There is no authentication: it is meant for a trusted
home network, and that was a deliberate call.

No SSE. FlyingFox only exposes `AsyncBufferedSequence<UInt8>`, which was fragile
in practice; the web UI polls instead, and suspends polling when the tab is
hidden.

## Naming

The app has three names, one per display width. All three are in
[`AppConfig`](../App/Sources/AppConfig.swift) and mirrored in `project.yml`.

| Form | Where it shows | Carried by |
| --- | --- | --- |
| `TBD` | menu bar, Share menu, Terminal, build product `TBD.app` | `PRODUCT_NAME`, `AppConfig.shortName` |
| `To Be Downloaded` | the app menu next to the Apple logo, in-app UI | `CFBundleName`, `AppConfig.displayName` |
| `TBD - To Be Downloaded` | Finder, Spotlight, Settings → Applications | **installed bundle name**, `CFBundleDisplayName`, `AppConfig.fullName` |

**The bundle is not named the same when built and when installed, on purpose.**
The build produces `TBD.app` (short paths in the repo, scripts and Terminal), but
it installs as `/Applications/TBD - To Be Downloaded.app`, because **Spotlight
indexes an app by its file name and ignores `CFBundleDisplayName`** — installed
as `TBD.app`, searching "to be downloaded" finds nothing (`mdls` then reports
`kMDItemDisplayName = "TBD"`).

Renaming a bundle's folder is harmless: the signature covers the contents, not
the name; the executable stays `Contents/MacOS/TBD`; and the updater's
`FileManager.replaceItemAt` keeps the **destination's** name, so the installed
name survives updates. Both `install.sh` and the Homebrew cask
(`app "TBD.app", target: "TBD - To Be Downloaded.app"`) install under it.

The URL scheme `tbd://` lives in `AppConfig.urlScheme`, which is **shared with
the extension target** — it used to be hardcoded on both sides, and a divergence
would have broken sharing silently.

## System entry points

| Entry point | State |
| --- | --- |
| **Services** menu → "Download with TBD" | works |
| URL scheme `tbd://download?url=…` | works |
| Global shortcut ⌥⌘V | works (opt-in in Settings) |
| **Share extension** (Safari's share sheet) | **inactive without an Apple signature** |

Incoming links are handled in `DownloadManager`, not in a view, so they work
with no window open. The global shortcut uses Carbon's `RegisterEventHotKey`: a
global `NSEvent` monitor would require the Accessibility permission.

Why the Share extension is inactive is covered in
[TROUBLESHOOTING.md](TROUBLESHOOTING.md#the-share-extension-doesnt-appear).

## Constraints to keep in mind

- **macOS 13** deployment target — no macOS 14+ API (`.onKeyPress`,
  `.background.secondary`, SwiftData…).
- **Swift 6** strict concurrency. `RelativeDateTimeFormatter` is not `Sendable`
  (instantiate at call site); `AnyTransition` is not either (declare as
  `static var`).
- **Not sandboxed**, ad-hoc signed, hardened runtime **off** — required only for
  Apple notarization, which needs a paid account. Flip
  `ENABLE_HARDENED_RUNTIME` to `YES` the day that changes.
- **arm64 only.**
