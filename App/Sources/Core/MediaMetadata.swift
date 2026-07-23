import Foundation

/// Métadonnées d'un média, extraites SANS téléchargement via
/// `yt-dlp --dump-single-json --skip-download`. Sert à l'aperçu (avant le
/// téléchargement) côté UI native et web.
struct MediaMetadata: Codable, Sendable, Equatable {
    var title: String
    var channel: String?
    /// Durée en secondes.
    var duration: Double?
    /// URL absolue de la miniature (chargée directement par le client).
    var thumbnailURL: String?

    /// Décode la sortie `--dump-single-json` de yt-dlp en ne gardant que les
    /// champs utiles. La charge complète est énorme : on ignore tout le reste.
    static func decode(from data: Data) -> MediaMetadata? {
        struct Raw: Decodable {
            let title: String?
            let uploader: String?
            let channel: String?
            let duration: Double?
            let thumbnail: String?
        }
        guard let raw = try? JSONDecoder().decode(Raw.self, from: data) else { return nil }
        let title = raw.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let title, !title.isEmpty else { return nil }
        return MediaMetadata(
            title: title,
            channel: raw.channel ?? raw.uploader,
            duration: raw.duration,
            thumbnailURL: raw.thumbnail
        )
    }
}
