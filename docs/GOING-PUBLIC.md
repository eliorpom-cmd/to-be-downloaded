# Going public

What stands between the private beta and an app anyone can install. Marketing
is not in here.

[RELEASING.md](RELEASING.md) covers cutting a version. This covers doing it for
the first time in the open.

## Before the repository becomes public

The moment it flips, everything in the history is readable by everyone,
forever. Most of this list is done; what is left is marked as such.

- [x] **The history was rewritten**, and this is the entry that matters most
      here. Removing the nonfree FFmpeg from the working tree left 91 MB of it
      reachable in every clone — `git clone` downloads objects, not the current
      snapshot, so publishing the repository would have redistributed the exact
      binary [THIRD-PARTY.md](THIRD-PARTY.md) explains nobody may redistribute.
      `git filter-repo --invert-paths` dropped `App/Resources/bin/ffmpeg` and
      `ffprobe` from all 19 commits (58 MB → 37 MB), and the French commit
      messages were translated in the same pass. Every hash below the initial
      commit changed. Nothing was lost: the tree of the last commit is
      byte-identical to what it was before.

      If a clone made before 2026-07-31 ever turns up, it still contains the
      binaries and must not be pushed anywhere.
- [x] **Searched the whole history for secrets**, not just the working tree.
      The Ed25519 private keys live in `~/.config/tbd-release/` and were never
      committed, which is the point. Nothing found — the only hit is the
      command itself, on the next line:

      ```bash
      git log -p --all | grep -nE 'BEGIN [A-Z ]*PRIVATE KEY|ghp_|gho_|sk-[A-Za-z0-9]'
      ```

      Worth re-running before the flip. Anything found means rewriting history
      again; rotating the key afterwards is not enough on its own.
- [x] **The commit messages are English and written for strangers.** They are
      part of the project's public voice, and the early ones were written for
      an audience of one.
- [x] **No path from the machine it was built on.** `/Users/elior/…` appears
      once, in this file, as the example of what to look for.
- [x] **LICENSE agrees with THIRD-PARTY.md**: AGPL-3.0 for the project's own
      code, the icon carved out in [NOTICE](../NOTICE), yt-dlp bundled under
      the Unlicense, FFmpeg downloaded rather than shipped. The web page also
      offers the source now, which is what AGPL §13 asks of a program used
      over a network — see `WebUI.indexHTML`.
- [ ] **Decide about issues and discussions.** Public repository, public bug
      tracker. If issues stay off, say where bugs go instead. Issues are on
      today, with templates in `.github/`, and that is the only item on this
      list still open.
- [ ] **Take the six README screenshots.** The `<img>` tags are commented out
      next to the shot each one wants, and `docs/assets/README.md` has the
      method. Not a blocker, but the README opens on an empty space until then.

## The Homebrew side

- [x] **`eliorpom-cmd/homebrew-tap` created public**, containing
      `Casks/to-be-downloaded.rb`. Public matters: a tap in a private
      repository fails for everyone but you, with an unhelpful error.
- [ ] **Copy the generated cask** from `dist/to-be-downloaded.rb` after each
      release, commit, push. `release.sh` regenerates it with the right
      `sha256` every time. Done for 1.0.0; it is the step to remember for
      every release after.
- [x] **Tested from a genuinely empty state** — untapped, untrusted,
      uninstalled. The cask resolves, the `sha256` matches, the app lands in
      `/Applications`.
- [ ] **Test on a Mac that has never seen the app.** A second Mac, or a fresh
      user account on this one. The build machine always works, which tells
      you nothing — and Gatekeeper is precisely what it cannot tell you about.
- [ ] **Verify `brew upgrade --cask to-be-downloaded`** picks up the next
      version. That is the fallback if both signing keys are ever lost.
- [ ] **Submit the cask to `homebrew/cask`** — possible again since 1.2.0.
      The official repository deprecates casks that fail Gatekeeper and removed
      them on **2026-09-01**; that deadline never applied to a personal tap, but
      it did shut the door to the official one. Notarization reopened it. Not
      urgent, and it means handing version bumps to strangers.

### `--no-quarantine` is gone, and it was the install command

Kept as a record: this is what shipping unnotarized cost, and 1.2.0 is what
ended it. Anyone reading an install command from 1.0.0 or 1.1.0 is reading this
era.

Homebrew removed the flag in **5.1**. It is not deprecated with a warning; the
option does not parse, so the published command installed nothing at all:

```
Error: invalid option: --no-quarantine
```

Homebrew removed the flag, not the capability — bypassing Gatekeeper is simply
no longer something a package manager does on the user's behalf. So the install
is two commands now, and the second is the same outcome the flag produced:

```bash
brew install --cask eliorpom-cmd/tap/to-be-downloaded
xattr -dr com.apple.quarantine "/Applications/TBD - To be downloaded.app"
```

Someone who skips the second line gets a refused launch and then **System
Settings → Privacy & Security → Open Anyway**. Control-click → Open, which most
of the web still recommends, was removed in macOS Sequoia.

## The updater, which only starts working in public

While the repository is private, the app asks GitHub for releases, gets a 404,
and treats it as "nothing published". Auto-update does nothing for beta
testers, by construction.

- [x] **First public release published as a normal release**, not a
      pre-release: the updater ignores drafts and pre-releases by design, so
      `v0.1.0` stayed invisible to it and `v1.0.0` is what it finally sees.
- [x] **Both files attached**, `TBD-<version>-macos.zip` and its `.sig`.
      Without the signature every installed app refuses the update. `TBD.dmg`
      rides along for people who will not open a terminal — under that exact
      name, unversioned, because the site links it through
      `releases/latest/download/TBD.dmg`.
- [ ] **Test an actual upgrade** between two published versions, on a Mac where
      the old one is installed. This is the one path that cannot be tested
      before the repository is public, and the one that breaks silently for
      everybody at once.
- [ ] **Confirm the backup key is not on the build machine.** A backup stored
      next to the original protects against nothing.

## Notarization — done, and what it took

Until 1.2.0 the app was ad-hoc signed: no hardened runtime, not notarized, and
an install that took a second command lifting the quarantine attribute. The cost
was never technical, it was that the one thing on the site which had to be
*explained* rather than stated was also the thing that looks most like a red
flag. Some people stopped there.

Four people paid for the Apple Developer account between them (see
[Supporters](../README.md#supporters)). What the switch actually took:

- [x] `ENABLE_HARDENED_RUNTIME` to `YES` in `project.yml`.
- [x] Sign with a Developer ID Application certificate instead of `-`. It
      **cannot be created with an App Store Connect API key** — Apple answers
      `This operation can only be performed by the Account Holder`. The CSR goes
      up by hand on the certificates page. [RELEASING.md](RELEASING.md#apple-signing)
      has the commands.
- [x] `--options runtime --timestamp` on every `codesign`. A missing secure
      timestamp is the most common notarization rejection there is.
- [x] **`--entitlements` on every `codesign`**, which was the real trap. The
      build runs `CODE_SIGNING_ALLOWED=NO` and signs by hand, so
      `CODE_SIGN_ENTITLEMENTS` from `project.yml` was never applied by anything —
      1.1.0 shipped publicly with an empty entitlement set and nobody could tell,
      because nothing needed them until the hardened runtime went on.
- [x] A separate `App/ytdlp.entitlements` for the bundled yt-dlp. Entitlements
      apply per executable, and only the PyInstaller binary needs executable
      memory and unvalidated libraries.
- [x] Notarization and stapling in `build.sh`, for the app **and** the DMG. Two
      separate tickets: without the second, Gatekeeper refuses the disk image
      before anyone reaches the app inside it.
- [x] The bundled yt-dlp still starts under the hardened runtime. Verified by
      running it, not by reasoning about it.
- [ ] Drop the `xattr` line from every page that prints it, and delete the
      Gatekeeper walkthrough on the disk-image path.

`release.sh` now asks the built app whether it is notarized instead of assuming,
and emits the cask's `caveats` accordingly — so a build that silently loses its
ticket cannot ship with an install command that claims otherwise.

## The day itself

- [x] Repository public.
- [ ] `SOURCE_PUBLIC = true` in the site's `config.ts`, which brings back the
      GitHub links and switches the "the code goes public when it leaves beta"
      sentence to the present tense.
- [ ] `LAUNCHED = true` in the same file, which replaces the waitlist form with
      the Homebrew command everywhere.
- [ ] Delete `src/pages/beta.astro` and `public/beta/`, which exist only
      because the repository was private.
- [ ] Email the waitlist. It is the only list that exists.
