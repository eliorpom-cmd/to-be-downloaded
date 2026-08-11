// TBD — To Be Downloaded. Copyright (C) 2026 Elior Pommier.
// Licensed under the GNU AGPL v3 or later. See LICENSE and NOTICE.
import Foundation

/// Media type to produce.
enum MediaKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case video
    case audio
    var id: String { rawValue }

    /// The container is no longer in the label: it's set separately
    /// (`AudioFormat`), and video always outputs as MP4.
    var label: String {
        switch self {
        case .video: return "Video"
        case .audio: return "Audio"
        }
    }
}

/// Video quality (max height in pixels; `max` = best available).
enum VideoQuality: Int, CaseIterable, Sendable, Identifiable {
    case p360 = 360
    case p480 = 480
    case p720 = 720
    case p1080 = 1080
    case max = 0

    var id: Int { rawValue }
    var label: String { self == .max ? "Max" : "\(rawValue)p" }
}

/// Which subtitle track to embed, when the video has one.
///
/// Deliberately short. yt-dlp accepts every language YouTube has, but a list
/// of two hundred entries is a worse answer than a list of nine: the ones
/// worth naming are the ones people actually read, and "System language"
/// covers everyone else without asking them anything.
enum SubtitleLanguage: String, CaseIterable, Sendable, Identifiable, Codable {
    case system
    case en, fr, es, de, it, pt, ja, ko, zh

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System language"
        case .en: return "English"
        case .fr: return "French"
        case .es: return "Spanish"
        case .de: return "German"
        case .it: return "Italian"
        case .pt: return "Portuguese"
        case .ja: return "Japanese"
        case .ko: return "Korean"
        case .zh: return "Chinese"
        }
    }

    /// Codes handed to `--sub-langs`, in preference order.
    ///
    /// English trails every other choice: it is the one language nearly every
    /// channel captions, so it is the fallback that stops "subtitles on"
    /// meaning "no subtitles" on a video that simply has none in yours.
    var codes: [String] {
        switch self {
        case .system:
            let current = Locale.current.language.languageCode?.identifier ?? "en"
            return current == "en" ? ["en"] : [current, "en"]
        case .en:
            return ["en"]
        default:
            return [rawValue, "en"]
        }
    }
}

/// MP3 audio bitrate.
enum AudioBitrate: Int, CaseIterable, Sendable, Identifiable {
    case k128 = 128
    case k192 = 192
    case k320 = 320

    var id: Int { rawValue }
    var label: String { "\(rawValue) kbps" }
}

/// Output audio container.
///
/// YouTube serves AAC: converting it to MP3 re-encodes it, degrading quality
/// and taking time. Keeping it as M4A avoids both — and AAC plays everywhere
/// (Apple, Windows, Android, car stereos). MP3 is still offered for old
/// hardware, which is the only thing that won't play it.
enum AudioFormat: String, CaseIterable, Sendable, Identifiable, Codable {
    case m4a
    case mp3

    var id: String { rawValue }

    var label: String {
        switch self {
        case .m4a: return "M4A"
        case .mp3: return "MP3"
        }
    }

    var detail: String {
        switch self {
        case .m4a: return "Keeps the original audio. No re-encoding, better quality."
        case .mp3: return "Re-encoded, for older devices that need it"
        }
    }

    /// Bitrate is adjustable only if we re-encode.
    var usesBitrate: Bool { self == .mp3 }
}

/// Complete download specification.
struct DownloadFormat: Sendable, Equatable, Codable {
    var kind: MediaKind
    var videoQuality: VideoQuality = .p1080
    var audioBitrate: AudioBitrate = .k192
    var audioFormat: AudioFormat = .m4a
    /// Embed subtitles in the MP4 (video only).
    var subtitles: Bool = false

    var shortLabel: String {
        switch kind {
        case .video: return "MP4 · \(videoQuality.label)"
        case .audio:
            return audioFormat.usesBitrate
                ? "\(audioFormat.label) · \(audioBitrate.label)"
                : "\(audioFormat.label) · original"
        }
    }
}

extension VideoQuality: Codable {}
extension AudioBitrate: Codable {}
