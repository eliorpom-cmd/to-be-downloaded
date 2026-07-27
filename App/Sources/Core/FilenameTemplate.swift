import Foundation

/// Comment nommer les fichiers produits.
///
/// L'app passait `--restrict-filenames` à yt-dlp, qui remplace tout espace par
/// un souligné et ampute les caractères accentués : on obtenait
/// `Rick_Astley_-_Never_Gonna_Give_You_Up_Official_Video_4K_Re…`. Sans cette
/// option, yt-dlp ne remplace que les caractères réellement interdits par le
/// système de fichiers, et le titre reste lisible.
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

    /// Aperçu montré sous le réglage, avec une vidéo réelle en exemple.
    var example: String {
        switch self {
        case .title:        return "Never Gonna Give You Up.mp4"
        case .channelTitle: return "Rick Astley — Never Gonna Give You Up.mp4"
        case .dateTitle:    return "2009-10-25 — Never Gonna Give You Up.mp4"
        case .custom:       return ""
        }
    }

    /// Motif yt-dlp correspondant, SANS l'extension (ajoutée par l'appelant).
    var pattern: String? {
        switch self {
        case .title:        return "%(title)s"
        case .channelTitle: return "%(uploader)s — %(title)s"
        case .dateTitle:    return "%(upload_date>%Y-%m-%d)s — %(title)s"
        case .custom:       return nil
        }
    }

    /// Motif complet à passer à `-o`, extension comprise.
    ///
    /// Un gabarit personnalisé est nettoyé avant usage : un `/` y créerait des
    /// sous-dossiers, ce que le réglage ne promet pas, et un motif vide ferait
    /// écrire un fichier sans nom.
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
