import Foundation

/// Validation of accepted links. Off-actor: called from drag-and-drop callbacks,
/// which do not run on the main actor.
enum YouTubeLink {

    /// Allowed hosts — the app downloads only from YouTube.
    static let allowedHosts: Set<String> = [
        "youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com",
        "youtu.be", "www.youtu.be",
    ]

    static func isValid(_ string: String) -> Bool {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              let host = url.host?.lowercased()
        else { return false }
        return allowedHosts.contains(host)
    }

    /// Video identifier, read directly from the URL.
    ///
    /// Used to display the thumbnail BEFORE any network response: querying
    /// yt-dlp takes several seconds, and the field would stay empty during that
    /// time even though the information is already there, in the pasted link.
    static func videoID(from string: String) -> String? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              let host = components.host?.lowercased(),
              allowedHosts.contains(host)
        else { return nil }

        // youtu.be/<id>
        if host.hasSuffix("youtu.be") {
            return sanitize(components.path.dropFirst())
        }
        // youtube.com/watch?v=<id>
        if let v = components.queryItems?.first(where: { $0.name == "v" })?.value {
            return sanitize(v)
        }
        // /shorts/<id>, /embed/<id>, /live/<id>, /v/<id>
        let parts = components.path.split(separator: "/")
        if parts.count >= 2, ["shorts", "embed", "live", "v"].contains(String(parts[0])) {
            return sanitize(parts[1])
        }
        return nil
    }

    /// A YouTube identifier is 11 characters of base64-url alphabet. We verify
    /// rather than trust the URL: this string goes into a thumbnail URL next.
    private static func sanitize(_ raw: some StringProtocol) -> String? {
        let id = String(raw)
        let allowed = CharacterSet(charactersIn:
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        guard id.count == 11, id.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        return id
    }

    /// Playlist identifier, if the link designates one.
    ///
    /// A link can carry BOTH: `watch?v=…&list=…` designates a video *inside*
    /// a playlist. This is the ambiguous case — hence the question asked to the
    /// user rather than a choice made for them.
    static func playlistID(from string: String) -> String? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              let host = components.host?.lowercased(),
              allowedHosts.contains(host),
              let list = components.queryItems?.first(where: { $0.name == "list" })?.value,
              !list.isEmpty
        else { return nil }
        // `RD…` = mix generated on-the-fly by YouTube, without stable content:
        // offering it would give a different list on each opening.
        guard !list.hasPrefix("RD") else { return nil }
        return list
    }

    /// Canonical URL of a playlist, without the current video.
    static func playlistURL(from string: String) -> String? {
        playlistID(from: string).map { "https://www.youtube.com/playlist?list=\($0)" }
    }

    /// Official thumbnail of a video, deducible without any network call.
    /// `mqdefault` (320×180) is plenty for the sizes we display it at.
    static func thumbnailURL(for string: String) -> String? {
        videoID(from: string).map { "https://i.ytimg.com/vi/\($0)/mqdefault.jpg" }
    }
}
