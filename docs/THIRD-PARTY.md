# Third-party components

TBD's own source is [AGPL-3.0](../LICENSE) (see also [NOTICE](../NOTICE)). It
ships and depends on other people's work, which keeps its own terms.

| Component | Where | License | Redistributable in a release? |
| --- | --- | --- | --- |
| [yt-dlp](https://github.com/yt-dlp/yt-dlp) (`yt-dlp_macos`) | bundled: `App/Resources/bin/yt-dlp` | Unlicense (public domain) | Yes |
| Python + `curl_cffi`, `certifi`, … inside that PyInstaller bundle | same file | PSF / MIT / MPL-2.0 | Yes |
| Mozilla CA bundle | bundled: `App/Resources/bin/cacert.pem` | MPL-2.0 | Yes |
| [FlyingFox](https://github.com/swhitty/FlyingFox) | SwiftPM dependency, statically linked | MIT | Yes |
| [FFmpeg](https://ffmpeg.org) + ffprobe | **not bundled** — downloaded on first launch | GPL v3 (publisher's build) | Not ours to redistribute — and we don't |
| App icon, by [Saint](https://x.com/app_settings) | bundled: `App/Resources/AppIcon.icon` | © its author, used here with permission | See [App icon](#app-icon) |
| GitHub and Instagram marks | bundled: `App/Resources/Logos/*.svg` | trademarks of their owners, used to link to profiles | See [Brand marks](#brand-marks) |

Not legal advice — it is the reading this repository acts on, and the reasoning
is laid out so you can check it.

---

## FFmpeg is downloaded, not bundled

TBD needs FFmpeg: yt-dlp calls it to mux video and audio, to remux M4A, to
encode MP3 and to embed subtitles, and TBD calls it directly to extract poster
frames. It is not optional. It is also not in the app bundle, and the first
launch fetches it (~56 MB) before anything can be downloaded.

That is not a size decision. It is a licensing one.

### What was wrong with the bundled build

The static build this project used to ship (from `eugeneware/ffmpeg-static`)
answered for itself:

```console
$ ffmpeg -L
This version of ffmpeg has nonfree parts compiled in.
Therefore it is not legally redistributable.
```

It had been configured with `--enable-gpl --enable-version3 --enable-nonfree`.
The last flag is the problem, and the arithmetic is short:

1. The only license granting anyone the right to redistribute FFmpeg's GPL parts
   is the GPL.
2. The GPL grants that right **only if** the whole combined work can be
   distributed under the GPL.
3. `--enable-nonfree` allows into the binary code the GPL forbids combining
   with — so the combined work cannot be distributed under the GPL.
4. Therefore no license permitted redistributing that binary. Not the GPL, not
   the AGPL, not MIT, not anything this repository could put on its own code.

Point 4 is the one that trips people up: **it had nothing to do with TBD's
license.** A license governs code you own. Nobody here owns FFmpeg, so the
choice between MIT, AGPL or anything else changed nothing about the right to
hand that binary out. A DMG, a GitHub release asset and a Homebrew cask are all redistribution,
and all were equally not permitted.

(Running it privately was always fine — the GPL never restricts private use.
Only distribution was blocked, which is exactly what shipping an app is.)

### Why downloading solves it

If the user's machine fetches FFmpeg from the party that *is* entitled to
distribute it, TBD is not the distributor and inherits no obligation. Nothing
in the repository, the DMG or the cask contains FFmpeg.

The cost is a one-time download and no offline first run. The side benefit is
real: the app went from **125 MB to 43 MB**, and the DMG from 77 MB to 38 MB.

The alternative would have been to compile a license-clean FFmpeg and keep
bundling it — TBD never re-encodes video, so an LGPL build with `libmp3lame`
and `libdav1d` would cover every call site. It stays a valid option if the
download ever becomes a problem; it just trades a network dependency for a build
pipeline and a source-offer obligation.

### Where it comes from, and what is checked

Source: **[ffmpeg.martin-riedl.de](https://ffmpeg.martin-riedl.de)**, macOS
arm64 release channel. Chosen because it is the only macOS Apple Silicon build
that checks every box:

- configured `--enable-gpl --enable-version3` and **no `--enable-nonfree`** — a
  plain GPL v3 build, which its publisher may lawfully distribute;
- native arm64;
- **signed with an Apple Developer ID** (team `KU3N25YGLU`), which matters on
  Apple Silicon, where an unsigned executable does not start at all;
- stable "latest" redirect URLs, with a `.sha256` published next to every
  archive.

[`FFmpegInstaller.swift`](../App/Sources/Core/FFmpegInstaller.swift) then:

1. **Resolves without downloading.** The `latest` URL answers `307` with the
   versioned path, which carries the version — a few bytes instead of 56 MB, and
   the basis for deciding whether anything needs downloading at all.
2. **Refuses unexpected hosts.** HTTPS on `ffmpeg.martin-riedl.de`, checked
   again on the redirect target and on the checksum URL.
3. **Verifies the published SHA-256.** This one comes from the same host as the
   archive, so it proves nothing about intent — it catches a truncated transfer,
   nothing more. It is not the security boundary.
4. **Verifies the Apple Developer ID signature** — anchored to Apple's root,
   with the Developer ID markers, pinned to team `KU3N25YGLU`
   ([`CodeSignature.swift`](../App/Sources/Core/CodeSignature.swift)). *This* is
   the security boundary: whoever takes over that web server can serve an
   archive and a matching checksum, but cannot sign in the name of an Apple
   team whose private key they do not have.
5. **Runs it once** (`-version`) before anything is installed.
6. **Installs atomically** into `~/Library/Application Support/TBD/bin`, never
   into the app bundle — writing there would break its signature, and
   `/Applications` is not always writable.

Any failure leaves the previous state untouched and is reported on screen with
a retry.

### Does FFmpeg's license reach TBD's own code?

No, and the structure is the reason.

TBD never links FFmpeg. It never includes an FFmpeg header. It spawns
`…/ffmpeg` as a separate process with an argument array and reads its output —
the same relationship any shell has with any command it runs. That is the
arm's-length boundary the GPL's "combined work" language is about, so FFmpeg
never dictated this repository's license. Since the binary is not even
distributed with the app anymore, the question is doubly moot.

(TBD's own license *is* AGPL-3.0 today, which is GPL-compatible anyway — but by
choice, not because FFmpeg forced it. The distinction matters: relicensing TBD
tomorrow would still be the author's call alone.)

---

## yt-dlp

Public domain (Unlicense) — no obligation beyond honesty about where it came
from. The bundled `yt-dlp_macos` is the official universal2 asset, **ad-hoc
signed at the source**, which matters on Apple Silicon for the same reason as
above.

It is only a **seed**. The copy TBD actually runs lives in
`~/Library/Application Support/TBD/bin/yt-dlp` and updates itself — see
[docs/UPDATES.md](UPDATES.md).

## FlyingFox

MIT, statically linked through SwiftPM, no framework embedded in the bundle.
Attribution in this file is the whole obligation.

## Brand marks

`App/Resources/Logos/github.svg` and `instagram.svg` are the official marks, as
published by [Simple Icons](https://simpleicons.org) (the collection is CC0; the
marks themselves stay the trademarks of GitHub, Inc. and Meta Platforms, Inc.).

They appear in **Settings → About**, at 14 pt, as the clickable glyph of a link
to the author's own profile on each platform — which is what a trademark may be
used for without permission: identifying the thing it names. They are not used
as TBD's own branding, and neither company endorses this app.

## App icon

The icon — `App/Resources/AppIcon.icon`, and the `mascot.svg` inside it — was
drawn by **Saint**, aka *System Settings*
([@app_settings](https://x.com/app_settings)). It is used in TBD with his
permission, and he is credited in the app under **Settings → Credits**.

**The repository's license covers the source code, not this artwork.** That is
the default position for any drawing: a file being in a public repository grants
nobody the right to reuse it. So if you fork TBD and ship your own build,
**replace the icon** with your own, or ask Saint yourself. Everything else in
here you may take under the terms listed above; the face is not part of the
deal.

(Practical bonus: your fork should not look like this app anyway. A different
icon is how a user tells two builds apart.)
