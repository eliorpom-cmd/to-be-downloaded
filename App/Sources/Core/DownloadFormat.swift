import Foundation

/// Type de média à produire.
enum MediaKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case video
    case audio
    var id: String { rawValue }

    /// Le conteneur n'est plus dans le libellé : il se règle à part
    /// (`AudioFormat`), et la vidéo sort toujours en MP4.
    var label: String {
        switch self {
        case .video: return "Video"
        case .audio: return "Audio"
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

/// Conteneur audio produit.
///
/// YouTube sert de l'AAC : le convertir en MP3 le ré-encode, donc dégrade et
/// prend du temps. Le garder en M4A évite les deux — et l'AAC se lit partout
/// (Apple, Windows, Android, autoradios). MP3 reste proposé pour le matériel
/// ancien, qui est la seule chose qui ne le lise pas.
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

    /// Le débit n'est réglable que si l'on ré-encode.
    var usesBitrate: Bool { self == .mp3 }
}

/// Spécification complète d'un téléchargement.
struct DownloadFormat: Sendable, Equatable, Codable {
    var kind: MediaKind
    var videoQuality: VideoQuality = .p1080
    var audioBitrate: AudioBitrate = .k192
    var audioFormat: AudioFormat = .m4a
    /// Incruster les sous-titres dans le MP4 (vidéo seulement).
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
