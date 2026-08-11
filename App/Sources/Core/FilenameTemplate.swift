// TBD — To Be Downloaded. Copyright (C) 2026 Elior Pommier.
// Licensed under the GNU AGPL v3 or later. See LICENSE and NOTICE.
import Foundation

/// How to name produced files.
///
/// The app passed `--restrict-filenames` to yt-dlp, which replaces every space
/// with an underscore and strips accented characters: we got
/// `Rick_Astley_-_Never_Gonna_Give_You_Up_Official_Video_4K_Re…`. Without
/// this option, yt-dlp only replaces characters truly forbidden by the
/// filesystem, and the title stays readable.
enum FilenameTemplate: String, CaseIterable, Identifiable, Sendable {
    case title
    case channelTitle
    case dateTitle
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .title:        return "Title"
        case .channelTitle: return "Channel — Title"
        case .dateTitle:    return "Date — Title"
        case .custom:       return "Custom…"
        }
    }

    /// Preview shown under the setting, with a real video as example.
    var example: String {
        switch self {
        case .title:        return "Never Gonna Give You Up.mp4"
        case .channelTitle: return "Rick Astley — Never Gonna Give You Up.mp4"
        case .dateTitle:    return "2009-10-25 — Never Gonna Give You Up.mp4"
        case .custom:       return ""
        }
    }

    /// Corresponding yt-dlp pattern, WITHOUT the extension (added by caller).
    var pattern: String? {
        switch self {
        case .title:        return "%(title)s"
        case .channelTitle: return "%(uploader)s — %(title)s"
        case .dateTitle:    return "%(upload_date>%Y-%m-%d)s — %(title)s"
        case .custom:       return nil
        }
    }

    /// Complete pattern to pass to `-o`, extension included.
    ///
    /// A custom template is cleaned before use: a `/` would create
    /// subfolders, which the setting does not promise, and an empty pattern
    /// would write a file with no name.
    static func outputPattern(_ template: FilenameTemplate, custom: String) -> String {
        let base: String
        if let pattern = template.pattern {
            base = pattern
        } else {
            let cleaned = custom
                .replacingOccurrences(of: "/", with: "-")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            base = cleaned.isEmpty ? "%(title)s" : cleaned
        }
        return base + ".%(ext)s"
    }
}
