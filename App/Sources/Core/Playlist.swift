import Foundation

/// Une playlist YouTube et ses vidéos, lues sans rien télécharger.
struct Playlist: Sendable, Equatable, Identifiable {
    /// Identité de présentation seulement (`.sheet(item:)`), pas d'identifiant
    /// YouTube : deux lectures de la même playlist sont deux objets distincts.
    let id = UUID()
    var title: String
    var entries: [Entry]

    struct Entry: Sendable, Equatable, Identifiable {
        let id: String          // identifiant vidéo YouTube
        var title: String
        var duration: Double?

        var url: String { "https://www.youtube.com/watch?v=\(id)" }
        var thumbnailURL: String { "https://i.ytimg.com/vi/\(id)/mqdefault.jpg" }
    }

    /// Décode `yt-dlp --flat-playlist --dump-single-json`.
    ///
    /// « Plat » veut dire qu'on ne demande QUE la liste : yt-dlp n'extrait
    /// aucune des vidéos. Sans cela, une playlist de cinquante titres
    /// demanderait cinquante extractions complètes avant d'afficher quoi que
    /// ce soit.
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
            // Les vidéos privées ou supprimées apparaissent sans titre
            // exploitable : les proposer au choix ne servirait à rien.
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
