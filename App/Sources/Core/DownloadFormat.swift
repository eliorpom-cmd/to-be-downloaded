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
        case .m4a: return "Keeps the original audio — no re-encoding, better quality"
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
