import Foundation

/// Un travail de téléchargement suivi par l'UI.
struct DownloadJob: Identifiable, Sendable {
    let id: UUID
    let url: String
    let format: DownloadFormat
    var state: State
    var progress: DownloadProgress?
    var fileURL: URL?
    var errorMessage: String?
    /// Métadonnées (titre, chaîne, miniature) récupérées au démarrage.
    var metadata: MediaMetadata?
    /// Taille du fichier final (octets), renseignée à la fin.
    var fileSize: Int64?

    init(url: String, format: DownloadFormat) {
        self.id = UUID()
        self.url = url
        self.format = format
        self.state = .queued
    }

    enum State: Sendable, Equatable {
        case queued
        case downloading
        case completed
        case failed
        case cancelled
    }

    /// Nom de fichier final (si terminé).
    var fileName: String? { fileURL?.lastPathComponent }

    /// Meilleur libellé à afficher : titre connu > nom de fichier > URL brute.
    var displayTitle: String {
        if let t = metadata?.title, !t.isEmpty { return t }
        return fileName ?? url
    }
}
