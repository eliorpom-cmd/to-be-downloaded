# Partial download (trim before downloading): design notes

17 October 2026. Thinking ahead for the next notable release (1.5 or 2.0). Nothing is built yet.

## Why this feature, and why now

- **It is what people come for.** On tbd.yt, `/blog/download-part-of-youtube-video/` is the most read page after
  the home page: 92 visits since August, 2.5× the next article (Downie alternative, 37). Umami, 17/10/2026.
- **The article currently admits the gap**: "the app I build does not expose this yet — it downloads whole
  videos". The top landing page sends its readers to a terminal command instead of the app.
- **It is a paid feature elsewhere.** Pulltube's headline feature is picking a start and an end. Those apps
  download the whole file and trim after; yt-dlp's `--download-sections` fetches only the range, which is faster
  (article test: 10 s out of a 10-minute 4K video = 93 KB in ~2 s, against 1.27 GB).

## What the user does

1. Pastes a link (or uses the menu bar, the share sheet, or the iPhone web UI) as today.
2. When the metadata arrives, a **Trim** button appears next to the format choice. Off by default: the default
   download stays exactly what it is today.
3. Trim opens a range bar the width of the window:
   - two handles, start and end, over a strip of thumbnails of the video (YouTube storyboards, see below);
   - two time fields under it, typed or adjusted with the arrow keys (`3:40`, `1:02:00`, `220` all accepted);
   - if the video has **chapters**, a menu "Chapter…" that sets both handles to a chapter;
   - the clip length and an estimated size shown live ("3 min 35 s · ~48 MB").
4. Download. The file is named with its range: `Title (3m40s–7m15s).mp4`.

Shortcuts:
- A link that carries a time (`?t=220`, `&t=3m40s`, `youtu.be/…?t=…`) opens with Trim on and the start handle
  already there. `YouTubeLink.swift` already parses links; it gains the timestamp.
- "From here to the end" and "The last N seconds" are one click each (`*220-inf`, `*-20-0`).

## How it works

### The yt-dlp side (already proven in the blog article)

```
--download-sections "*220.0-435.0"
```

added to `DownloadEngine.buildArgs` when the job has a range, with three constraints:

1. **DASH formats only.** With the muxed format 18, FFmpeg's byte-range request gets **403 / ffmpeg exited with
   code 8**. Today's selector ends with fallbacks `b[height<=h]` and `/b`, which can pick a muxed stream. In
   trim mode, drop those fallbacks and keep only `bv*+ba` selectors. If no DASH pair exists, say so before
   starting rather than failing after.
2. **Exact cuts**: `--force-keyframes-at-cuts`. Without it the cut lands on the nearest keyframe, up to a second
   or two off, which looks like a bug to someone who placed a handle precisely. On by default, with a setting
   "Faster, less precise cuts" for people who trim long ranges. It re-encodes only around the cut points.
3. **Audio only** works the same way with `-f bestaudio[ext=m4a]`.

### Progress (the real engineering risk)

With `--download-sections`, yt-dlp hands the download to FFmpeg, and **the progress template stops reporting**:
the bar would sit at 0 % until the end. FFmpeg prints `time=00:00:12.34` on stderr. `DownloadProgress` needs a
second parser: progress = `time` / clip length. Must be verified on a real run first, because this is where the
feature can feel broken while working.

### Thumbnails on the range bar

yt-dlp lists YouTube **storyboards** as formats (`sb0`, `sb1`…: grids of small images at fixed intervals) in the
same `--dump-single-json` call the app already makes for metadata. The bar draws those tiles, no video player
needed. Fallback when absent (other sites): plain bar with the time fields.

A real video preview (play the range before downloading) is out of scope for the first version: it means
embedding a player and streaming, which is a different product.

### Where the range lives

- `DownloadJob` gains `range: ClosedRange<Double>?` (seconds). `nil` = whole video, so every existing path is
  untouched.
- `MediaMetadata` gains `chapters` and `storyboard` (both in the JSON already fetched).
- `FilenameTemplate` appends the range.
- `LibraryStore` keeps the range, so the library shows "3:40–7:15" under the title.
- Web UI and API: `POST /api/download` accepts optional `start` / `end` (seconds). The iPhone page gets two time
  fields, no thumbnails, in the first version.

## Edge cases

| Case | Behaviour |
| --- | --- |
| End past the duration | clamped to the duration |
| Start ≥ end | Download button disabled, the fields say why |
| Live stream in progress | Trim hidden (sections on a live stream need `--live-from-start`, a separate project) |
| Playlist | Trim hidden: one range does not mean anything across videos |
| Subtitles embedded | kept, cut to the range by FFmpeg (to verify) |
| Video without chapters | no Chapter menu |

## Tests

- Unit: timestamp parsing (`3:40`, `1:02:00`, `220`, `3m40s`, `?t=` forms), argument building with a range
  (sections flag present, no muxed fallback, keyframes flag), FFmpeg progress line parsing, filename with range.
- One real run, kept as a manual check in `docs/RELEASING.md`: 10 seconds from a Creative Commons video, file
  duration checked with `ffprobe` against the asked range (±0.1 s with exact cuts).

## Size of the work

Roughly 2 to 3 days: engine and progress (1 day), range bar with storyboards and chapters (1 day), web UI, API,
library, tests and the release check (0.5 to 1 day).

## After shipping

- Rewrite the end of the blog article: "TBD does this with two handles" plus the download button, on the page
  that already brings the most readers.
- A short screen recording of the range bar for the release post: this is the feature to lead the release with.

## Open questions for Elior

1. Exact cuts on by default (slower, precise) or keyframe cuts (instant, up to ~2 s off)? Proposed: exact.
2. Several ranges from one video in one go (yt-dlp supports it, one file per range)? Proposed: not in the first
   version.
3. Free or Pro, if TBD gets a paid tier? It is the feature competitors charge for.
