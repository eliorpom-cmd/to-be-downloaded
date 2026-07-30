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

            var bytes: Int64? { filesize ?? filesize_approx }
            var isVideoOnly: Bool { (acodec ?? "none") == "none" && (vcodec ?? "none") != "none" }
            var isAudioOnly: Bool { (vcodec ?? "none") == "none" && (acodec ?? "none") != "none" }
            var isH264: Bool { (vcodec ?? "").hasPrefix("avc1") }
        }
        struct Raw: Decodable {
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

        if let formats = raw.formats {
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
