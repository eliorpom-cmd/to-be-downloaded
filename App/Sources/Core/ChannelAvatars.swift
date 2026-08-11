// TBD — To Be Downloaded. Copyright (C) 2026 Elior Pommier.
// Licensed under the GNU AGPL v3 or later. See LICENSE and NOTICE.
import Foundation

/// YouTube channel profile photo.
///
/// No cheap source provides it: oEmbed only returns the channel name and
/// URL, and `yt-dlp --dump-single-json` on a video only exposes
/// `channel_id` / `uploader_url`. Asking yt-dlp for the channel URL works,
/// but costs ~16 s — out of the question for a 28 pt thumbnail.
///
/// So we read the CHANNEL PAGE (~2 s), and especially CACHE by
/// channel: the cost is paid once per channel, not per download. Someone who
/// watches three channels pays it three times total.
///
/// It's decoration: if it fails, we fall back to the channel's initial,
/// and nothing else depends on it.
actor ChannelAvatars {
    static let shared = ChannelAvatars()

    /// Key = channel identifier (`@handle` or `UC…`), value = avatar URL.
    private var cache: [String: String] = [:]
    private var loaded = false
    /// In-flight resolutions, to avoid downloading the same page twice when
    /// launching multiple videos from the same channel in a row.
    private var inFlight: [String: Task<String?, Never>] = [:]

    private var fileURL: URL {
        AppConfig.supportDirectory
            // `-v2`: v1 entries were read from the video page
            // and often pointed to a recommended channel, not the right one. A
            // new filename discards them without migration code.
            .appendingPathComponent("channel-avatars-v2.json")
    }

    /// Channel avatar. `channelKey` serves as cache key, `channelURL` is
    /// the page actually downloaded.
    func avatarURL(channelKey: String, channelURL: String) async -> String? {
        load()
        if let cached = cache[channelKey] { return cached }
        if let running = inFlight[channelKey] { return await running.value }

        let task = Task<String?, Never> { await Self.scrape(channelURL: channelURL) }
        inFlight[channelKey] = task
        let found = await task.value
        inFlight[channelKey] = nil

        if let found {
            cache[channelKey] = found
            save()
        }
        return found
    }

    // MARK: - Extraction

    /// `og:image` from the channel page: by definition THIS channel's avatar,
    /// whatever the page content.
    ///
    /// Don't fall back to the video page: its `yt3` URLs are mostly from
    /// recommended channels in the right column, and the owner's avatar
    /// isn't reliably identifiable there. Taking "the first" gave another
    /// channel's avatar.
    ///
    /// The size template is renormalized to get a crisp image without
    /// fetching the 900 px that `og:image` serves.
    private static func scrape(channelURL: String) async -> String? {
        guard let url = URL(string: channelURL) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        // A browser User-Agent avoids the lightweight variants YouTube
        // reserves for unknown clients.
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
                + "(KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent")
        // In Europe, a request without a consent cookie is redirected to
        // `consent.youtube.com`, whose page obviously doesn't contain
        // the avatar. `SOCS=CAI` is the "choice already made" marker; we set it
        // manually rather than relying on the shared cookie store, whose
        // contents depend on what the app did before (hence an avatar that
        // appeared or not depending on the time).
        request.httpShouldHandleCookies = false
        request.setValue("SOCS=CAI", forHTTPHeaderField: "Cookie")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let html = String(data: data, encoding: .utf8)
        else { return nil }

        // The host varies (`yt3.ggpht.com`, `yt3.googleusercontent.com`) and the
        // path may have a `ytc/` prefix: we only anchor on `yt3.`.
        let pattern = #"<meta property="og:image" content="(https://yt3\.[^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html)
        else { return nil }

        let raw = String(html[range])
        // `=s900-` → `=s176-`: the thumbnail is 28 pt, or 84 px at 3×.
        return raw.replacingOccurrences(
            of: #"=s\d+-"#, with: "=s176-", options: .regularExpression)
    }

    // MARK: - Persistance

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        else { return }
        cache = decoded
    }

    private func save() {
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
