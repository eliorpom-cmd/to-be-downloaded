import Foundation

/// Requête de téléchargement reçue de l'UI web.
struct DownloadRequestDTO: Codable, Sendable {
    let url: String
    let kind: String        // "video" | "audio"
    let quality: String?    // "360".."1080" / "max"  ou  "128".."320"

    func toFormat() -> DownloadFormat {
        let mediaKind = MediaKind(rawValue: kind) ?? .video
        var format = DownloadFormat(kind: mediaKind)
        if let quality {
            switch mediaKind {
            case .video:
                if quality.lowercased() == "max" {
                    format.videoQuality = .max
                } else if let h = Int(quality), let q = VideoQuality(rawValue: h) {
                    format.videoQuality = q
                }
            case .audio:
                if let b = Int(quality), let br = AudioBitrate(rawValue: b) {
                    format.audioBitrate = br
                }
            }
        }
        return format
    }
}

/// Instantané d'un job exposé en JSON à l'UI web.
struct JobDTO: Codable, Sendable {
    let id: String
    let title: String
    let channel: String?
    let thumbnail: String?
    let format: String
    let state: String
    let fraction: Double?
    let downloaded: Int64?
    let total: Int64?
    let speed: Double?
    let eta: Double?
    let fileName: String?
    let fileSize: Int64?
    let error: String?
    let canFetch: Bool

    init(_ job: DownloadJob) {
        id = job.id.uuidString
        title = job.displayTitle
        channel = job.metadata?.channel
        thumbnail = job.metadata?.thumbnailURL
        format = job.format.shortLabel
        state = job.state.apiValue
        fraction = job.progress?.fraction
        downloaded = job.progress?.downloadedBytes
        total = job.progress?.totalBytes
        speed = job.progress?.speed
        eta = job.progress?.eta
        fileName = job.fileName
        fileSize = job.fileSize
        error = job.errorMessage
        canFetch = job.state == .completed && job.fileURL != nil
    }
}

/// Aperçu métadonnées exposé à l'UI web (endpoint /api/metadata).
struct MetadataDTO: Codable, Sendable {
    let title: String
    let channel: String?
    let duration: Double?
    let thumbnail: String?

    init(_ meta: MediaMetadata) {
        title = meta.title
        channel = meta.channel
        duration = meta.duration
        thumbnail = meta.thumbnailURL
    }
}

extension DownloadJob.State {
    var apiValue: String {
        switch self {
        case .queued:      return "queued"
        case .downloading: return "downloading"
        case .completed:   return "completed"
        case .failed:      return "failed"
        case .cancelled:   return "cancelled"
        }
    }
}
