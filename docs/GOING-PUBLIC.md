# Going public

What stands between the private beta and an app anyone can install. Marketing
is not in here.

[RELEASING.md](RELEASING.md) covers cutting a version. This covers doing it for
the first time in the open.

## Before the repository becomes public

The moment it flips, everything in the history is readable by everyone,
forever. Check in this order.

- [ ] **Search the whole history for secrets**, not just the working tree. The
      Ed25519 private keys live in `~/.config/tbd-release/` and were never
      committed, which is the point, but check anyway:

      ```bash
      git log -p --all | grep -nE 'BEGIN [A-Z ]*PRIVATE KEY|ghp_|gho_|sk-[A-Za-z0-9]'
      ```

      Anything found means rewriting history or starting a fresh repository.
      Rotating the key afterwards is not enough on its own.
- [ ] **Read the commit messages.** They become part of the project's public
      voice, and the early ones were written for an audience of one.
- [ ] **Check every path in the code and docs** for the machine it was built
      on: `/Users/elior/…` in a comment is harmless but reads as unfinished.
- [ ] **LICENSE is present and correct** for a project that bundles yt-dlp
      (Unlicense) and downloads FFmpeg (GPL/LGPL depending on the build).
      [THIRD-PARTY.md](THIRD-PARTY.md) already has the reasoning; the licence
      file has to agree with it.
- [ ] **Decide about issues and discussions.** Public repository, public bug
      tracker. If issues stay off, say where bugs go instead.

## The Homebrew side

- [ ] **Create `eliorpom-cmd/homebrew-tap`** as a public repository containing
      `Casks/to-be-downloaded.rb`. Public matters: a tap in a private
      repository fails for everyone but you, with an unhelpful error.
- [ ] **Copy the generated cask** from `dist/to-be-downloaded.rb` after each
      release, commit, push. `release.sh` regenerates it with the right
      `sha256` every time.
- [ ] **Test the command on a Mac that has never seen the app**, from a
      genuinely empty state:

      ```bash
      brew uninstall --cask to-be-downloaded 2>/dev/null
      brew untap eliorpom-cmd/tap 2>/dev/null
      brew install --cask --no-quarantine eliorpom-cmd/tap/to-be-downloaded
      ```

      A second Mac, or a fresh user account on this one. The build machine
      always works, which tells you nothing.
- [ ] **Verify `brew upgrade --cask to-be-downloaded`** picks up the next
      version. That is the fallback if both signing keys are ever lost.
- [ ] Later, and only once the project has some visible traction: submitting
      the cask to `homebrew/cask` removes the tap from the install command
      entirely and gets install counts published on formulae.brew.sh for free.
      It has notability requirements the project does not meet yet.

## The updater, which only starts working in public

While the repository is private, the app asks GitHub for releases, gets a 404,
and treats it as "nothing published". Auto-update does nothing for beta
testers, by construction.

- [ ] **Publish the first public release as a normal release**, not a
      pre-release: the updater ignores drafts and pre-releases by design, so
      `v0.1.0` will stay invisible to it.
- [ ] **Attach both files**, `TBD-<version>-macos.zip` and its `.sig`. Without
      the signature every installed app refuses the update.
- [ ] **Test an actual upgrade** between two published versions, on a Mac where
      the old one is installed. This is the one path that cannot be tested
      before the repository is public, and the one that breaks silently for
      everybody at once.
- [ ] **Confirm the backup key is not on the build machine.** A backup stored
      next to the original protects against nothing.

## Notarization, or the choice not to

Today the app is ad-hoc signed: no hardened runtime, not notarized, and the
install command needs `--no-quarantine`. That flag is a real cost. It is the
one thing on the site that has to be explained rather than stated, and some
people will stop there.

Fixing it costs 99 € a year for an Apple Developer account, plus:

- [ ] switch `ENABLE_HARDENED_RUNTIME` to `YES` in `project.yml` (the comment
      there already says so),
- [ ] sign with a Developer ID certificate instead of `-`,
- [ ] add a notarization step to `build.sh` (`xcrun notarytool submit --wait`,
      then `xcrun stapler staple`),
- [ ] drop `--no-quarantine` from the cask and from every page that prints the
      command,
- [ ] check that the bundled yt-dlp still starts: signing a PyInstaller binary
      under the hardened runtime is exactly what the
      `com.apple.security.cs.allow-*` entitlements are there for.

Decide it on purpose, not by drift. Shipping unsigned is a defensible choice
for a free tool; pretending the flag is a detail is not.

## The day itself

- [ ] Repository public.
- [ ] `SOURCE_PUBLIC = true` in the site's `config.ts`, which brings back the
      GitHub links and switches the "the code goes public when it leaves beta"
      sentence to the present tense.
- [ ] `LAUNCHED = true` in the same file, which replaces the waitlist form with
      the Homebrew command everywhere.
- [ ] Delete `src/pages/beta.astro` and `public/beta/`, which exist only
      because the repository was private.
- [ ] Email the waitlist. It is the only list that exists.
