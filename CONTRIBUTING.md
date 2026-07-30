# Contributing

Thanks for looking. This is a small, opinionated app maintained by one person —
issues and pull requests are welcome, and so is the possibility that a feature is
turned down because it doesn't fit.

## Before you start

- **Open an issue first** for anything beyond a bug fix. It costs you five
  minutes and can save you an afternoon of work on something that won't be
  merged.
- Read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). Several non-obvious
  decisions in there are load-bearing, and the comments explaining them are as
  important as the code.

## Setting up

```bash
brew install xcodegen
xcodegen generate
open TBD.xcodeproj
```

Full details, including the gotchas that cost debugging sessions, are in
[docs/BUILDING.md](docs/BUILDING.md).

`TBD.xcodeproj` is generated and git-ignored — **edit `project.yml`**, and re-run
`xcodegen generate` after adding or removing a Swift file.

## Ground rules

- **macOS 13 is the deployment target.** No macOS 14+ API.
- **Swift 6 strict concurrency**, no warnings.
- **Never invoke a shell.** Subprocesses take an argument array
  (`ProcessRunner`), always. No string interpolation into a command line.
- **Never read a subprocess pipe after `waitUntilExit`.** It deadlocks past
  64 KB; there is a war story about it in the architecture doc.
- **No new third-party dependency** without discussing it in an issue. The
  bundled binaries already carry enough licensing weight — see
  [docs/THIRD-PARTY.md](docs/THIRD-PARTY.md).
- **The UI is monochrome and stays monochrome.** State is conveyed by a 1pt
  border, a glyph, and text weight — never by color. The only color in the app is
  the window's traffic lights.
- **All user-facing strings are in English.** The app is not localized.

## Code style

Follow the surrounding code: Swift API Design Guidelines, no reformatting of
untouched lines, comments that say *why* rather than *what*. Engine code
(`App/Sources/Core/`) contains no SwiftUI.

Source comments are currently in French, UI strings and documentation in English.
Match the file you're editing rather than converting it.

## Pull requests

- One subject per PR.
- Say what you tested and how. Anything network-facing usually needs a real
  download, which CI cannot do.
- Update `CHANGELOG.md` under `Unreleased` if the change is user-visible.
- Update the relevant doc under `docs/` if you change behavior it describes.

## Licensing of contributions

TBD is [AGPL-3.0](LICENSE), and your contribution goes in under that same
license — nothing surprising there.

There is one extra term, and it is worth stating plainly rather than burying:
**by opening a pull request you also grant Elior Pommier a perpetual,
worldwide, irrevocable, royalty-free right to use your contribution under other
licenses, including commercial ones.** You keep your copyright; you are not
signing it away, and your contribution stays AGPL for everyone else, forever.

Why it's asked: the copyright holder can only offer a paid commercial license
for code he is allowed to relicense. One merged patch without this grant would
lock that door for the whole project. Contributors who would rather not grant it
are welcome to say so in the PR — the change can usually be reimplemented, or
kept as a fork, without hard feelings.

Add a `Signed-off-by:` line to your commits (`git commit -s`) to certify that
the work is yours to submit and that you accept the above.

## Reporting a bug

Use the issue template. What actually helps:

- macOS version and Mac model (Apple Silicon only — Intel is unsupported).
- App version (Settings → About) and yt-dlp version (Settings → Engine).
- The link that failed, if it isn't private — many bugs are site-specific.
- What the app showed, verbatim.

Downloads that fail with "sign in to confirm you're not a bot", HTTP 403, or
"requested format is not available" are usually **yt-dlp** being out of date
against a YouTube change, not TBD. Hit **Update** in Settings → Engine, or switch
to the nightly channel, before filing.

## Security

Do not open a public issue for a vulnerability — see [SECURITY.md](SECURITY.md).
