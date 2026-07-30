# Releasing

> Never add FFmpeg back into `App/Resources/bin/`. The app fetches it on first
> launch precisely so that nothing this project distributes contains it — see
> [THIRD-PARTY.md](THIRD-PARTY.md#ffmpeg-is-downloaded-not-bundled).

## One-time setup

```bash
./scripts/signing.swift keygen           # current key  — once, ever
./scripts/signing.swift keygen backup    # backup key   — store it ELSEWHERE
```

Private keys go to `~/.config/tbd-release/` (`0600`, outside the repo). The
public halves belong in `AppConfig.updatePublicKeys`.

The **backup key must not stay on the build machine** — a backup sitting next to
the original protects against nothing. Why there are two keys at all is explained
in [UPDATES.md](UPDATES.md#security-model-of-the-app-updater).

The Homebrew tap is a separate repository, created once: a GitHub repo named
`homebrew-tap` (so `eliorpom-cmd/homebrew-tap`) containing
`Casks/to-be-downloaded.rb`. `release.sh` regenerates that file on every release;
you copy it in and push.

## Cutting a version

```bash
./scripts/release.sh 0.2.0            # signed with the current key
./scripts/release.sh 0.2.0 backup     # signed with the backup key
```

The script:

1. bumps `MARKETING_VERSION` in `project.yml`,
2. refreshes the bundled yt-dlp to latest stable,
3. runs `build.sh` (Release build, ad-hoc signature, DMG),
4. archives with `ditto -c -k --sequesterRsrc --keepParent`,
5. signs the ZIP with Ed25519,
6. generates the Homebrew cask with its `sha256`,
7. prints the `gh release create` command.

**It never publishes anything.** Everything lands in `dist/`; publishing stays an
explicit decision.

Guard rails it enforces, each of which would otherwise ship a broken release:

- the git remote and `AppConfig.updateRepository` must match, or installed apps
  would look for updates in the wrong place;
- the built bundle's `CFBundleShortVersionString` must equal the tag, because the
  updater refuses an archive that announces anything else;
- the private key used must correspond to a public key in `AppConfig`, or nobody
  could install what you just published.

## Publishing

Attach **both** files to the GitHub release: `TBD-<version>-macos.zip` **and**
`TBD-<version>-macos.zip.sig`. Without the signature, every installed app will
refuse the update. Drafts and pre-releases are ignored by the updater by design;
a 404 from the releases API means "nothing published yet" and is not treated as
an error.

Then update the tap: copy the generated `Casks/to-be-downloaded.rb` into
`eliorpom-cmd/homebrew-tap` and push.

## If a key is lost

1. **Current key lost** → sign the next version with the backup
   (`./scripts/release.sh <version> backup`). Nothing breaks for anyone. In that
   version, replace the current key with a fresh one in `updatePublicKeys`
   (never removing keys already published) and generate a new backup.
2. **Both keys lost** → in-app updates stop there, distribution does not. Users
   remain reachable through Homebrew (`brew upgrade --cask to-be-downloaded`),
   which verifies the cask's `sha256`. Publish a version carrying new keys.
   Annoying, not fatal.

## Renaming the repository

Free as long as no release exists. After that, two places: `AppConfig.updateRepository`
(what the app queries) and the tap's `brew` command. `release.sh` derives the repo
from the git remote and **refuses to build** if the two disagree.

Note that the cask token and the repository name are independent — the `brew`
command does not contain the repo name.

## Checklist

- [ ] `CHANGELOG.md` updated
- [ ] bundled yt-dlp refreshed (`release.sh` does it)
- [ ] `App/Resources/bin/` still contains only `yt-dlp` and `cacert.pem`
- [ ] `./scripts/release.sh <version>` green
- [ ] `.zip` **and** `.zip.sig` attached to the release
- [ ] cask copied to the tap and pushed
- [ ] fresh-machine install tested (quarantine path included)
