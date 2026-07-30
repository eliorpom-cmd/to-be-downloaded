import Foundation
import SwiftUI

/// A persisted library entry: an actual produced file.
/// Unlike `DownloadJob` (session queue), this survives app restart.
struct LibraryItem: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    var title: String
    var channel: String?
    var thumbnailURL: String?
    /// Format label as displayed ("MP4 · 1080p").
    var formatLabel: String
    var kind: MediaKind
    /// Path of the final file. Stored as string to stay Codable/stable.
    var filePath: String
    var fileSize: Int64?
    var addedAt: Date
    /// Original YouTube URL, for "Download Again" and "Copy Link".
    var sourceURL: String

    var fileURL: URL { URL(fileURLWithPath: filePath) }

    /// Is the file still there? (The user might have moved it.)
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

/// Persistent library of completed downloads.
///
/// Storage: plain JSON in Application Support. No SwiftData — the app targets
/// macOS 13 and a flat file is more than enough for this volume, while staying
/// readable/repairable by hand.
@MainActor
final class LibraryStore: ObservableObject {

    @Published private(set) var items: [LibraryItem] = []

    private let fileURL: URL

    init() {
        fileURL = AppConfig.supportDirectory.appendingPathComponent("library.json")
        load()
    }

    // MARK: - Reading

    /// Most recent entries first.
    var sorted: [LibraryItem] { items.sorted { $0.addedAt > $1.addedAt } }

    func matching(_ query: String) -> [LibraryItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return sorted }
        return sorted.filter {
            $0.title.lowercased().contains(q) || ($0.channel?.lowercased().contains(q) ?? false)
        }
    }

    /// Existing entry for the same video and media type.
    ///
    /// Comparison is on the YouTube identifier, not the URL: the same link
    /// writes ten ways (`youtu.be`, `t=` parameter, `si=` sharing, etc.) and
    /// comparing strings would almost never detect anything.
    func existing(forURL url: String, kind: MediaKind) -> LibraryItem? {
        guard let videoID = YouTubeLink.videoID(from: url) else { return nil }
        return sorted.first {
            $0.kind == kind
                && $0.fileExists
                && YouTubeLink.videoID(from: $0.sourceURL) == videoID
        }
    }

    // MARK: - Writing

    /// Record a completed job. Idempotent: replay without duplicating.
    func add(job: DownloadJob, fileURL url: URL) {
        var item = LibraryItem(job: job, fileURL: url)
        // Size not set by the job (file written just after the event): re-read
        // it from disk.
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

    /// Remove entries whose file disappeared from disk.
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

    // MARK: - Persistence

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
