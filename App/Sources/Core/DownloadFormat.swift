import Foundation

/// Type de média à produire.
enum MediaKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case video
    case audio
    var id: String { rawValue }

    var label: String {
        switch self {
        case .video: return "Video MP4"
        case .audio: return "Audio MP3"
        }
    }
}

/// Qualité vidéo (hauteur max en pixels ; `max` = meilleure dispo).
enum VideoQuality: Int, CaseIterable, Sendable, Identifiable {
    case p360 = 360
    case p480 = 480
    case p720 = 720
    case p1080 = 1080
    case max = 0

    var id: Int { rawValue }
    var label: String { self == .max ? "Max" : "\(rawValue)p" }
}

/// Débit audio MP3.
enum AudioBitrate: Int, CaseIterable, Sendable, Identifiable {
    case k128 = 128
    case k192 = 192
    case k320 = 320

    var id: Int { rawValue }
    var label: String { "\(rawValue) kbps" }
}

/// Spécification complète d'un téléchargement.
struct DownloadFormat: Sendable, Equatable {
    var kind: MediaKind
    var videoQuality: VideoQuality = .p1080
    var audioBitrate: AudioBitrate = .k192

    var shortLabel: String {
        switch kind {
        case .video: return "MP4 · \(videoQuality.label)"
        case .audio: return "MP3 · \(audioBitrate.label)"
        }
    }
}
