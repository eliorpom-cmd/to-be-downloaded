# Screenshots for the README

`icon.png` is generated (the composed macOS icon, rendered from
`App/Resources/AppIcon.icon`). The rest are **still to be captured** — the README
already points at these exact filenames, so dropping the files here is all it
takes.

How to capture a window cleanly: `⌘⇧4`, then **Space**, then click the window.
macOS keeps the rounded corners and the shadow, on a transparent background.
Retina is fine — GitHub scales it down, and the README pins the display width.

| File | Shot | Notes |
| --- | --- | --- |
| `hero.png` | The whole window, **Download** screen | Light theme. One download in progress (~60 %) and one finished, so the filling capsule is visible. This is the first thing anyone sees. |
| `clipboard.png` | Close-up of the URL field | Light theme, with the clipboard glyph showing inside the field. Crop to the field and the segmented control, not the whole window. |
| `progress.png` | Two or three stacked capsules | **Dark** theme — the fill reads better. Ideally one downloading, one `Merging`, one `Complete`. |
| `network.png` | The **Network Access** screen | With the QR code. Blurring the last octet of the IP is fine if you'd rather. |
| `library.png` | The **Library** screen | A handful of entries with their thumbnails. Pick videos you don't mind being public. |
| `webui.png` | *(optional)* the web UI on an iPhone | Not referenced yet — add it next to `network.png` if you take it. |
| `menubar.png` | *(optional)* the menu bar item, open | Same. |

Keep them lossless-ish but reasonable: a 1600 px-wide PNG is plenty, and
`pngquant` or **Preview → Export → reduce quality** keeps the repo light.
