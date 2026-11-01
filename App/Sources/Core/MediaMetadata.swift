// TBD — To Be Downloaded. Copyright (C) 2026 Elior Pommier.
// Licensed under the GNU AGPL v3 or later. See LICENSE and NOTICE.
import Foundation

/// Media metadata, extracted WITHOUT downloading via
/// `yt-dlp --dump-single-json --skip-download`. Used for preview (before
/// download) on native UI and web.
struct MediaMetadata: Codable, Sendable, Equatable {
    var title: String
    var channel: String?
    /// Duration in seconds.
    var duration: Double?
    /// Absolute URL of the video thumbnail (loaded by the client).
    var thumbnailURL: String?
    /// Channel page, when known (`https://youtube.com/@handle`).
    var channelURL: String?
    /// Channel profile photo, resolved separately (see `ChannelAvatars`).
    var channelAvatarURL: String?

    /// Estimated size of final file by video height (key 0 = "Max"),
    /// including audio track. Computed once from the format list.
    var videoBytes: [Int: Int64]?
    /// Size of the best audio track alone.
    var audioBytes: Int64?

    /// Chapters set by the channel, in order. Empty when there are none.
    var chapters: [Chapter] = []
    /// Grids of small images at fixed intervals, drawn under the trim bar.
    var storyboard: Storyboard?
    /// A stream that is live right now: it cannot be trimmed (sections of a
    /// live stream need `--live-from-start`, a separate project).
    var isLive = false

    struct Chapter: Codable, Sendable, Equatable, Hashable {
        var title: String
        var start: Double
        var end: Double
        var range: ClipRange { ClipRange(start: start, end: end) }
    }

    /// Decode yt-dlp's `--dump-single-json` output keeping only useful fields.
    /// The full payload is huge: ignore everything else.
    static func decode(from data: Data) -> MediaMetadata? {
        struct RawFormat: Decodable {
            let height: Int?
            let vcodec: String?
            let acodec: String?
            let abr: Double?
            let filesize: Int64?
            let filesize_approx: Int64?
            let format_id: String?
            let width: Int?
            let rows: Int?
            let columns: Int?
            let fps: Double?
            let fragments: [RawFragment]?

            var bytes: Int64? { filesize ?? filesize_approx }
            var isVideoOnly: Bool { (acodec ?? "none") == "none" && (vcodec ?? "none") != "none" }
            var isAudioOnly: Bool { (vcodec ?? "none") == "none" && (acodec ?? "none") != "none" }
            var isH264: Bool { (vcodec ?? "").hasPrefix("avc1") }
        }
        struct RawFragment: Decodable {
            let url: String?
        }
        struct RawChapter: Decodable {
            let title: String?
            let start_time: Double?
            let end_time: Double?
        }
        struct Raw: Decodable {
            let chapters: [RawChapter]?
            let live_status: String?
            let is_live: Bool?
            let title: String?
            let uploader: String?
            let channel: String?
            let duration: Double?
            let thumbnail: String?
            let formats: [RawFormat]?
        }
        guard let raw = try? JSONDecoder().decode(Raw.self, from: data) else { return nil }
        let title = raw.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let title, !title.isEmpty else { return nil }

        var metadata = MediaMetadata(
            title: title,
            channel: raw.channel ?? raw.uploader,
            duration: raw.duration,
            thumbnailURL: raw.thumbnail
        )

        metadata.isLive = raw.is_live == true || raw.live_status == "is_live"
        metadata.chapters = (raw.chapters ?? []).enumerated().compactMap { index, chapter in
            guard let start = chapter.start_time, let end = chapter.end_time, end > start
            else { return nil }
            let title = chapter.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            return Chapter(title: (title?.isEmpty == false ? title! : "Chapter \(index + 1)"),
                           start: start, end: end)
        }

        if let formats = raw.formats {
            metadata.storyboard = Storyboard.pick(from: formats.compactMap { f in
                guard f.format_id?.hasPrefix("sb") == true,
                      let width = f.width, let height = f.height,
                      let rows = f.rows, let columns = f.columns,
                      let fps = f.fps, fps > 0
                else { return nil }
                let sheets = (f.fragments ?? []).compactMap(\.url)
                guard !sheets.isEmpty else { return nil }
                return Storyboard(tileWidth: width, tileHeight: height, rows: rows,
                                  columns: columns, secondsPerTile: 1 / fps, sheets: sheets)
            })

            let audio = formats.filter { $0.isAudioOnly && $0.bytes != nil }
            // The track picked for download is the best available: estimate
            // with the same.
            let bestAudio = audio.max { ($0.abr ?? 0) < ($1.abr ?? 0) }
            metadata.audioBytes = bestAudio?.bytes

            let video = formats.filter { $0.isVideoOnly && $0.height != nil && $0.bytes != nil }
            var sizes: [Int: Int64] = [:]
            for target in VideoQuality.allCases {
                let candidates = target == .max
                    ? video
                    : video.filter { $0.height! <= target.rawValue }
                // Same preference order as `-f` selector: resolution first,
                // H.264 at equal resolution.
                guard let best = candidates.max(by: { a, b in
                    a.height! != b.height! ? a.height! < b.height!
                        : (a.isH264 ? 0 : 1) > (b.isH264 ? 0 : 1)
                }) else { continue }
                sizes[target.rawValue] = (best.bytes ?? 0) + (bestAudio?.bytes ?? 0)
            }
            metadata.videoBytes = sizes.isEmpty ? nil : sizes
        }

        return metadata
    }

    /// Expected size of the produced file for a given format, `nil` if formats
    /// have not been read yet. This is an ESTIMATE: yt-dlp itself knows only
    /// approximately the size of fragmented streams.
    func estimatedBytes(for format: DownloadFormat) -> Int64? {
        switch format.kind {
        case .video:
            return videoBytes?[format.videoQuality.rawValue]
        case .audio:
            switch format.audioFormat {
            case .m4a:
                return audioBytes
            case .mp3:
                // MP3 is re-encoded at constant bitrate: its size is deduced
                // from duration, not from the source's.
                guard let duration, duration > 0 else { return nil }
                return Int64(duration * Double(format.audioBitrate.rawValue) * 1000 / 8)
            }
        }
    }

    /// Expected size of a clip. A share of the whole file for audio, which is
    /// copied; for video, the picture is re-encoded at a known bitrate, so
    /// the size follows that bitrate rather than the source's.
    func estimatedBytes(for format: DownloadFormat, range: ClipRange) -> Int64? {
        let length = range.length
        guard length > 0 else { return nil }
        switch format.kind {
        case .video:
            let videoRate = Double(DownloadEngine.clipVideoKilobits(for: format.videoQuality))
                * 1_000 / 8
            var audioRate = 128_000.0 / 8
            if let audioBytes, let duration, duration > 0 {
                audioRate = Double(audioBytes) / duration
            }
            return Int64((videoRate + audioRate) * length)
        case .audio:
            guard let whole = estimatedBytes(for: format), let duration, duration > 0
            else { return nil }
            return Int64(Double(whole) * min(1, length / duration))
        }
    }

    /// Title and channel from YouTube's public oEmbed endpoint.
    ///
    /// `yt-dlp --dump-single-json` launches a Python interpreter and extracts
    /// the whole page: several seconds, during which the input shows neither
    /// title nor channel. oEmbed replies in a JSON request of hundreds of
    /// milliseconds. We use it to populate the display right away, yt-dlp
    /// completing later (duration, formats).
    ///
    /// No consequence on failure: it is a shortcut, not a source.
    static func oEmbed(for url: String) async -> MediaMetadata? {
        guard YouTubeLink.isValid(url),
              var components = URLComponents(string: "https://www.youtube.com/oembed")
        else { return nil }
        components.queryItems = [
            URLQueryItem(name: "url", value: url),
            URLQueryItem(name: "format", value: "json"),
        ]
        guard let endpoint = components.url else { return nil }

        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 5
        request.setValue("\(AppConfig.shortName)/\(AppConfig.version)",
                         forHTTPHeaderField: "User-Agent")

        struct Payload: Decodable {
            let title: String?
            let author_name: String?
            let author_url: String?
            let thumbnail_url: String?
        }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let payload = try? JSONDecoder().decode(Payload.self, from: data),
              let title = payload.title?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty
        else { return nil }

        return MediaMetadata(
            title: title,
            channel: payload.author_name,
            duration: nil,
            thumbnailURL: payload.thumbnail_url,
            channelURL: payload.author_url
        )
    }

    /// Cache key of a channel: the `@handle` or `UC…` identifier extracted
    /// from the channel URL. Stable, unlike the displayed name.
    var channelKey: String? {
        guard let channelURL, let url = URL(string: channelURL) else { return nil }
        let last = url.lastPathComponent
        return last.isEmpty ? nil : last
    }
}

/// YouTube's storyboard: sheets of small images taken at a fixed interval,
/// listed by yt-dlp as `sb0`…`sb3` formats in the metadata already fetched.
/// Enough to draw a strip of thumbnails under the trim bar, with no player.
struct Storyboard: Codable, Sendable, Equatable {
    var tileWidth: Int
    var tileHeight: Int
    var rows: Int
    var columns: Int
    var secondsPerTile: Double
    /// Image URLs, one per sheet of `rows × columns` tiles.
    var sheets: [String]

    var tilesPerSheet: Int { max(1, rows * columns) }

    /// Where the image for a given time is: which sheet, and the tile's
    /// top-left corner in pixels within it.
    func tile(at seconds: Double) -> (sheet: Int, x: Int, y: Int)? {
        guard secondsPerTile > 0, !sheets.isEmpty else { return nil }
        let index = max(0, Int(seconds / secondsPerTile))
        let sheet = min(index / tilesPerSheet, sheets.count - 1)
        // Past the last tile (the end of the video): the last one there is.
        let within = sheet == index / tilesPerSheet ? index % tilesPerSheet : tilesPerSheet - 1
        return (sheet, (within % columns) * tileWidth, (within / columns) * tileHeight)
    }

    /// The level that draws best at the trim bar's size: tiles about 80 px
    /// wide (`sb2` on YouTube), larger only if that is all there is.
    static func pick(from candidates: [Storyboard]) -> Storyboard? {
        candidates.min { a, b in
            abs(a.tileWidth - 80) < abs(b.tileWidth - 80)
        }
    }
}
