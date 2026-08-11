// TBD — To Be Downloaded. Copyright (C) 2026 Elior Pommier.
// Licensed under the GNU AGPL v3 or later. See LICENSE and NOTICE.
import Foundation

/// A YouTube playlist and its videos, read without downloading anything.
struct Playlist: Sendable, Equatable, Identifiable {
    /// Presentation identity only (`.sheet(item:)`), not a YouTube identifier:
    /// two reads of the same playlist are two distinct objects.
    let id = UUID()
    var title: String
    var entries: [Entry]

    struct Entry: Sendable, Equatable, Identifiable {
        let id: String          // YouTube video identifier
        var title: String
        var duration: Double?

        var url: String { "https://www.youtube.com/watch?v=\(id)" }
        var thumbnailURL: String { "https://i.ytimg.com/vi/\(id)/mqdefault.jpg" }
    }

    /// Decode `yt-dlp --flat-playlist --dump-single-json`.
    ///
    /// "Flat" means we request ONLY the list: yt-dlp extracts none of the
    /// videos. Without it, a fifty-video playlist would require fifty complete
    /// extractions before displaying anything.
    static func decode(from data: Data) -> Playlist? {
        struct RawEntry: Decodable {
            let id: String?
            let title: String?
            let duration: Double?
        }
        struct Raw: Decodable {
            let title: String?
            let entries: [RawEntry]?
        }
        guard let raw = try? JSONDecoder().decode(Raw.self, from: data),
              let rawEntries = raw.entries
        else { return nil }

        let entries = rawEntries.compactMap { entry -> Entry? in
            guard let id = entry.id, !id.isEmpty else { return nil }
            // Private or deleted videos appear without usable title: offering
            // them for choice would be pointless.
            let title = entry.title ?? ""
            guard !title.isEmpty, title != "[Private video]", title != "[Deleted video]"
            else { return nil }
            return Entry(id: id, title: title, duration: entry.duration)
        }
        guard !entries.isEmpty else { return nil }

        return Playlist(
            title: raw.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Playlist",
            entries: entries)
    }
}
