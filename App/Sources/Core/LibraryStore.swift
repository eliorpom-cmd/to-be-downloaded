import Foundation
import SwiftUI

/// Une entrée persistée de la bibliothèque : un fichier réellement produit.
/// Contrairement à `DownloadJob` (file d'attente de la session), ceci survit
/// au redémarrage de l'app.
struct LibraryItem: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    var title: String
    var channel: String?
    var thumbnailURL: String?
    /// Libellé du format tel qu'affiché (« MP4 · 1080p »).
    var formatLabel: String
    var kind: MediaKind
    /// Chemin du fichier final. Stocké en chaîne pour rester Codable/stable.
    var filePath: String
    var fileSize: Int64?
    var addedAt: Date
    /// URL YouTube d'origine, pour « Download Again » et « Copy Link ».
    var sourceURL: String

    var fileURL: URL { URL(fileURLWithPath: filePath) }

    /// Le fichier est-il toujours là ? (L'utilisateur peut l'avoir déplacé.)
    var fileExists: Bool { FileManager.default.fileExists(atPath: filePath) }

    init(job: DownloadJob, fileURL: URL) {
        self.id = job.id
        self.title = job.displayTitle
        self.channel = job.metadata?.channel
        self.thumbnailURL = job.metadata?.thumbnailURL
        self.formatLabel = job.format.shortLabel
        self.kind = job.format.kind
        self.filePath = fileURL.path
        self.fileSize = job.fileSize
        self.addedAt = Date()
        self.sourceURL = job.url
    }
}

/// Bibliothèque persistante des téléchargements terminés.
///
/// Stockage : un simple JSON dans Application Support. Pas de SwiftData —
/// l'app cible macOS 13 et un fichier plat suffit largement pour cette volumétrie,
/// tout en restant lisible/réparable à la main.
@MainActor
final class LibraryStore: ObservableObject {

    @Published private(set) var items: [LibraryItem] = []

    private let fileURL: URL

    init() {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support")
        let directory = support.appendingPathComponent(AppConfig.displayName, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("library.json")
        load()
    }

    // MARK: - Lecture

    /// Entrées les plus récentes d'abord.
    var sorted: [LibraryItem] { items.sorted { $0.addedAt > $1.addedAt } }

    func matching(_ query: String) -> [LibraryItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return sorted }
        return sorted.filter {
            $0.title.lowercased().contains(q) || ($0.channel?.lowercased().contains(q) ?? false)
        }
    }

    /// Entrée existante pour la même vidéo et le même type de média.
    ///
    /// La comparaison porte sur l'identifiant YouTube, pas sur l'URL : le même
    /// lien s'écrit de dix façons (`youtu.be`, paramètre `t=`, `si=` de
    /// partage…) et comparer les chaînes ne détecterait presque jamais rien.
    func existing(forURL url: String, kind: MediaKind) -> LibraryItem? {
        guard let videoID = YouTubeLink.videoID(from: url) else { return nil }
        return sorted.first {
            $0.kind == kind
                && $0.fileExists
                && YouTubeLink.videoID(from: $0.sourceURL) == videoID
        }
    }

    // MARK: - Écriture

    /// Enregistre un job terminé. Idempotent : rejoue sans dupliquer.
    func add(job: DownloadJob, fileURL url: URL) {
        var item = LibraryItem(job: job, fileURL: url)
        // Taille non renseignée par le job (fichier écrit juste après l'event) :
        // on la relit sur le disque.
        if item.fileSize == nil,
           let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize {
            item.fileSize = Int64(size)
        }
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        } else {
            items.append(item)
        }
        save()
    }

    func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
        PosterFrame.removeCache(for: id)
        save()
    }

    /// Retire les entrées dont le fichier a disparu du disque.
    func pruneMissingFiles() {
        let before = items.count
        items.removeAll { !$0.fileExists }
        if items.count != before { save() }
    }

    func removeAll() {
        for item in items { PosterFrame.removeCache(for: item.id) }
        items.removeAll()
        save()
    }

    // MARK: - Persistance

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        items = (try? decoder.decode([LibraryItem].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(items) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
