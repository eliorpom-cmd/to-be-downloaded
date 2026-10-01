# JavaScript runtime for yt-dlp: which one TBD should ship

Research note, 30 September 2026. Nothing in the app changes on this branch:
this is the study and the integration plan. Measurements were taken on a Linux
x86_64 cloud machine (4-core Xeon, 2.8 GHz), **not on a Mac**; macOS arm64
sizes below are read from the official macOS release assets themselves.

## Verdict

**Bundle QuickJS-NG (1.3 MB, MIT) as TBD's JavaScript runtime, and let a
user-installed Deno take over automatically when one exists.** Do not ship
Deno, do not ship Node or Bun, and do not add a PO token provider.

## What the problem actually is

The TODO said "PO tokens", but two different YouTube mechanisms are mixed up
under that name, and only one of them concerns TBD today.

1. **JS challenges (n / signature).** Since late 2025, yt-dlp solves them by
   running the `yt-dlp-ejs` scripts in an *external* JavaScript runtime. The
   scripts are already inside the official `yt-dlp_macos` binary TBD ships
   (`yt_dlp_ejs-0.8.0` in yt-dlp 2026.08.19); only the runtime is missing.
2. **PO tokens (proof of origin).** Needed by the `web`, `mweb`, `ios`,
   `android`… clients for HTTPS/DASH streams. **None of yt-dlp's default clients
   needs one**: in 2026.08.19 the defaults are `visionos` (no JS player, no PO
   token) and `web` (HLS formats, for which a PO token is only "recommended").

What TBD does today, read from the yt-dlp 2026.08.19 source
(`_get_requested_clients`):

- TBD never passes `--js-runtimes`, and a GUI app's `PATH` does not contain
  `/opt/homebrew/bin`, so even a user who installed Deno with Homebrew gets
  **no runtime**.
- Without a runtime yt-dlp falls back to `visionos` alone and prints *"YouTube
  extraction without a JS runtime has been deprecated, and some formats may be
  missing"*. TBD's metadata call passes `--no-warnings`, so nobody sees it.
- "Made for kids" videos fail with `visionos`, and the fallback yt-dlp has for
  them (`web_embedded`, `tv_downgraded`) is **only tried when a JS runtime is
  available**.

So the concrete gain of a runtime is: the default client pair instead of the
deprecated one-client fallback, "made for kids" videos, and resilience the day
YouTube breaks `visionos`. Not PO tokens.

## Options

| | Deno 2.9.7 | Node 24.21 | Bun 1.3.14 | **QuickJS-NG 0.17.0** | Apple WebKit JSI plugin |
|---|---|---|---|---|---|
| macOS arm64 executable | 81.0 MB | 122.1 MB | 63.1 MB | **1.3 MB** | 0 (system JavaScriptCore) + 136 KB of Python |
| Download (archive) | 38.5 MB zip | 52.9 MB tar.gz | 23.6 MB zip | 1.3 MB raw | — |
| yt-dlp status | recommended, on by default | `--js-runtimes node` | **deprecated**, >1.3.14 unsupported | `--js-runtimes quickjs` | third-party plugin |
| yt-dlp preference when several exist | 1000 | 900 | 800 | 850 | — |
| Sandbox of the solver | no FS, no network | partial | none | none (temp file per run) | WebView |
| Solver time, 3.1 MB input (Linux) | 0.27–0.37 s | 0.31–0.38 s | 0.29–0.35 s | **4.25–4.53 s** | not measurable here |
| Peak memory | 165–181 MB | 148–150 MB | 147–166 MB | 140–154 MB | — |
| macOS signature | Developer ID, Deno Land Inc. `2H4KBF436B` | Developer ID, Node.js Foundation `HX7739G8FX` | Developer ID, Jarred Sumner `7FRXF46ZSN` | **ad-hoc only**, links `libSystem` alone | — |
| License | MIT | MIT | MIT (links WebKit's JSC, LGPL parts) | MIT | Apache-2.0 |
| Maintenance | weekly releases, company-backed | foundation | active, but dropped by yt-dlp | 8 releases in 2026, last 18/09/2026 | a yt-dlp maintainer; last commit 23/04/2026 |

Notes:

- **Sizes**: the TODO's "150 MB" for Deno does not match today's asset; the
  macOS arm64 `deno` is 81 MB (Linux x86_64: 95.8 MB). It is still 60 times
  QuickJS-NG, and almost twice the whole app (43 MB).
- **Speed**: the input was `@babel/standalone`'s `babel.min.js` (3.1 MB,
  comparable to YouTube's ~2.7 MB `base.js`), run through the exact script
  yt-dlp builds. The solver parses it, then stops at "unexpected structure", so
  these numbers are a **lower bound dominated by parsing**. YouTube itself is
  blocked from the machine the measurement ran on, so no real player was solved.
  QuickJS-NG is about **14× slower** than the JIT runtimes. yt-dlp caches the
  preprocessed player (`output_preprocessed`), so that cost is paid once per
  YouTube player version (they roll every few days), not once per video.
- **All four runtimes are detected** by yt-dlp 2026.08.19
  (`[debug] JS runtimes: bun-1.3.14, deno-2.9.7, node-22.22.2, quickjs-ng-0.17.0`).
- **Apple WebKit JSI** ([grqz/yt-dlp-apple-webkit-jsi](https://github.com/grqz/yt-dlp-apple-webkit-jsi))
  is the only zero-byte option, and JIT-fast. It is set aside for now: it hooks
  `EJSBaseJCP`, which yt-dlp documents as a **private** API that may break
  without notice, and TBD updates yt-dlp on its own, so a break would land on
  users without a release. Worth a look again if the API goes public.
- **PO token providers** (`bgutil-ytdlp-pot-provider`, `yt-dlp-getpot-wpc`):
  the first needs Node or Deno plus its own script or HTTP server, the second a
  browser. Heavier than the problem, for clients TBD does not use.

## Why QuickJS-NG and not a downloaded Deno

Downloading Deno at first launch would fit the existing FFmpeg pattern exactly
(Developer ID pinned to a team, like `KU3N25YGLU` for FFmpeg), and it is 14×
faster. But it adds 38 MB to the first launch and 81 MB on disk to solve a
problem that costs a few seconds once every few days. QuickJS-NG is small
enough to bundle, so it works offline, on first launch, with no extra download
and no new failure screen. MIT means bundling it asks for nothing but the
attribution line.

And Deno is not excluded: yt-dlp ranks it above QuickJS (1000 vs 850), so if
TBD also passes the user's own Deno when one exists, it wins automatically.

## Integration plan (next minor release — 1.2.0 already shipped, so 1.3)

1. **`scripts/update-qjs.sh`**, modelled on `update-ytdlp.sh`: download
   `qjs-darwin-arm64` from `quickjs-ng/quickjs` releases into
   `App/Resources/bin/qjs`. QuickJS-NG publishes **no checksum**, so pin the
   SHA-256 in the script per version (v0.17.0:
   `8be3ddfe3397d2e692e4e1e8972ee9d032a0a580505d2f8b4ea528cf1b651c11`) and
   update it deliberately. Run `qjs --help` before replacing the file.
   The executable must be named `qjs`, or yt-dlp needs the full file path.
2. **`scripts/build.sh`**: add `qjs` to the signing loop (`for bin in yt-dlp`).
   It replaces the ad-hoc signature with the Developer ID one, hardened runtime
   and timestamp. **No entitlements**: QuickJS is an interpreter, no JIT, no
   unsigned libraries. Check `codesign --verify --strict` and notarization.
3. **`BinaryLocator`**: `effectiveJSRuntimes()` returns the arguments:
   - `--js-runtimes quickjs:<bundle>/Contents/Resources/bin/qjs` always
     (read-only in the bundle; unlike yt-dlp it is not self-updated, it moves
     with app releases);
   - plus `--js-runtimes deno:/opt/homebrew/bin/deno` (or `/usr/local/bin/deno`,
     `~/.deno/bin/deno`) when that file exists and is executable.
4. **`DownloadEngine`**: append those arguments to the three calls
   (`fetchMetadata`, `fetchPlaylist`, `buildArgs`). Keep the argument array,
   no shell string.
5. **Cache**: make sure nothing passes `--no-cache-dir`, since the
   preprocessed player cache is what makes QuickJS's cost a once-per-player
   one. Optionally point `--cache-dir` at `Application Support/TBD/cache` so it
   lives next to the rest of TBD's state.
6. **Docs**: `docs/THIRD-PARTY.md` (QuickJS-NG, MIT, bundled, ~1.3 MB),
   `NOTICE`, `docs/ARCHITECTURE.md` (the bundled runtime), `CHANGELOG.md`.
7. **Checks on a Mac** (could not be done here):
   - `yt-dlp -v` from the app shows `JS runtimes: quickjs-ng-0.17.0` and
     `[jsc]` provider `quickjs` available;
   - timing of the first extraction after emptying the cache, then the second,
     with QuickJS and with Deno, on a real YouTube video (the numbers above are
     a Linux lower bound);
   - a "made for kids" video that fails today and should download after;
   - the notarized build launches `qjs` from yt-dlp under the hardened runtime.

If step 7 shows the first extraction above ~10 s on an M1, the fallback is the
FFmpeg-style download of Deno (`2H4KBF436B` pin), offered rather than forced.

## Reproduce

```bash
scripts/research/js-runtime-bench.py path/to/player.js \
  deno=/opt/homebrew/bin/deno qjs=./qjs node=/usr/local/bin/node
```

Sources: yt-dlp wiki [EJS](https://github.com/yt-dlp/yt-dlp/wiki/EJS) and
[PO Token Guide](https://github.com/yt-dlp/yt-dlp/wiki/PO-Token-Guide);
yt-dlp 2026.08.19 source (`extractor/youtube/_video.py`, `_base.py`,
`jsc/_builtin/*.py`); [yt-dlp/ejs](https://github.com/yt-dlp/ejs) README;
release assets of Deno, Node, Bun and QuickJS-NG, downloaded 30/09/2026.

## Measured on a Mac (2026-10-01)

Apple Silicon Mac, QuickJS-NG 0.17.0 (`qjs-darwin-arm64`, 1.3 MB, runs after `xattr -c`), Homebrew yt-dlp 2026.07.04, real YouTube player `57bae81f` (2.98 MB).

- Bench script, solver alone, 3 runs each: Deno 0.42–0.45 s, Node 0.37–0.39 s, **QuickJS-NG 2.85 s** (about 7× slower, not 14×; memory 230 MB vs 310 MB).
- End to end, `yt-dlp -s --js-runtimes quickjs:…` after `--rm-cache-dir`: the run that solves the challenge takes 6.2 s, the others 1.5–1.6 s. Deno: 1.6–2.2 s. So QuickJS costs about **4.5 s once per player version**, then nothing.
- `yt-dlp -v` lists `JS runtimes: quickjs-ng-0.17.0` and the `quickjs` challenge provider; no warning.

Verdict unchanged: QuickJS-NG is fast enough to ship. Not checked here: a "made for kids" video, and the `yt-dlp_macos` binary the app ships.
