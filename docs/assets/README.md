# Screenshots for the README

`icon.png` is generated (the composed macOS icon, rendered from
`App/Resources/AppIcon.icon`). Four more came over from the site
(`tbd-site/public/media/`), downscaled with `sips -Z`. Two slots are **still to
be captured** — the README already points at those exact filenames, so dropping
the files here is all it takes.

How to capture a window cleanly: `⌘⇧4`, then **Space**, then click the window.
macOS keeps the rounded corners and the shadow, on a transparent background.
Retina is fine — GitHub scales it down, and the README pins the display width.

## Retaking them

`./scripts/screenshots.sh` redoes `hero.png`, `library.png` and `network.png`
here, and `app-hero.png` and `private-settings.png` in the website repository.
It hides every other app and the desktop icons, puts the window at a fixed
size in the middle of the screen, and walks the sidebar by name rather than by
coordinates, so it survives the layout changing.

It sets up no content: whatever is in the Library is what the Library shot
shows. Put a few downloads in it first.

`menubar.png` and `webui.png` are still taken by hand — a status item menu
closes as soon as anything else takes the focus, and the web page needs a
phone.

| File | In place | Shot | Notes |
| --- | --- | --- | --- |
| `hero.png` | 1640 × 1173 | The whole window, **Download** screen | Dark theme, one finished capsule. Worth re-taking one day with a download at ~60 % so the filling capsule shows. This is the first thing anyone sees. |
| `clipboard.png` | — **to take** | Close-up of the URL field | Light theme, with the clipboard glyph showing inside the field. Crop to the field and the segmented control, not the whole window. |
| `progress.png` | — **to take** | Two or three stacked capsules | **Dark** theme — the fill reads better. Ideally one downloading, one `Merging`, one `Complete`. |
| `network.png` | 1400 × 1001 | The **Remote Control** screen, running | With the QR code. The IP shown is a phone hotspot, nothing to blur. Re-take needed: the screen was renamed and the off state now explains the feature. |
| `library.png` | 1400 × 1001 | The **Library** screen | One entry. More entries with thumbnails would sell it better. |
| `menubar.png` | 920 × 600 | The menu bar item, open | Sits under the Library shot, in *It behaves like a Mac app*. |
| `webui.png` | — *(optional)* | The web UI on an iPhone | Referenced only by a comment — uncomment it next to `network.png` once taken. |

Keep them lossless-ish but reasonable: a 1600 px-wide PNG is plenty, and
`pngquant` or **Preview → Export → reduce quality** keeps the repo light.
