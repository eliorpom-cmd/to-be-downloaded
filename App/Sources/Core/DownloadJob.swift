// TBD — To Be Downloaded. Copyright (C) 2026 Elior Pommier.
// Licensed under the GNU AGPL v3 or later. See LICENSE and NOTICE.
import Foundation

/// A download job tracked by the UI.
struct DownloadJob: Identifiable, Sendable {
    let id: UUID
    let url: String
    let format: DownloadFormat
    var state: State
    var progress: DownloadProgress?
    var fileURL: URL?
    var errorMessage: String?
    /// Metadata (title, channel, thumbnail) fetched on startup.
    var metadata: MediaMetadata?
    /// Final file size (bytes), populated at the end.
    var fileSize: Int64?

    /// OVERALL progress displayed in [0...1].
    ///
    /// yt-dlp thinks in streams: a video downloads in two passes (video then
    /// audio), each from 0 to 100%, before ffmpeg assembly. Painted as-is, the
    /// indicator would fill the capsule, empty it, fill it again.
    /// We project each phase onto a portion of the bar, and we NEVER go back:
    /// progress that recedes is a lie.
    var overallProgress: Double = 0
    /// Index of the current stream (0 = first file downloaded).
    var streamIndex: Int = 0
    /// Current file, to detect the switch to the next stream.
    var currentStreamFile: String?
    /// Start of post-processing, to advance the bar during assembly.
    var mergeStartedAt: Date?

    /// Explicit `id` on restore: it designates the partial-file folder,
    /// the only way to resume where we left off.
    init(url: String, format: DownloadFormat, id: UUID = UUID()) {
        self.id = id
        self.url = url
        self.format = format
        self.state = .queued
    }

    enum State: Sendable, Equatable {
        case queued
        case downloading
        /// yt-dlp process suspended (SIGSTOP). Resumes where it left off.
        case paused
        /// Download complete, ffmpeg assembles the streams (or extracts audio).
        case merging
        case completed
        case failed
        case cancelled

        /// The job still occupies the engine (Dock badge, "Downloading" section).
        var isActive: Bool {
            switch self {
            case .queued, .downloading, .paused, .merging: return true
            case .completed, .failed, .cancelled: return false
            }
        }

        /// A progress bar makes sense in this state.
        var showsProgress: Bool {
            switch self {
            case .downloading, .paused, .merging: return true
            default: return false
            }
        }
    }

    /// Fraction to paint in the capsule: a single bar, from download start
    /// to assembly end.
    var progressFraction: Double? {
        switch state {
        case .completed: return 1
        case .downloading, .paused, .merging: return overallProgress
        case .queued: return 0
        default: return nil
        }
    }

    /// Portion of the bar assigned to a phase.
    ///
    /// The weights reflect actual time spent: the video track dominates,
    /// audio is short, assembly is shorter still. A video goes through
    /// 0→58% (video), 58→88% (audio), 88→100% (assembly); an MP3 has
    /// only one stream, then extraction.
    static func phaseSpan(streamIndex: Int, kind: MediaKind) -> ClosedRange<Double> {
        switch kind {
        case .audio:
            return streamIndex == 0 ? 0...0.85 : 0.85...0.92
        case .video:
            switch streamIndex {
            case 0:  return 0...0.58
            case 1:  return 0.58...0.88
            default: return 0.88...0.92
            }
        }
    }

    /// Where the download stops and post-processing begins.
    var postProcessingFloor: Double {
        switch format.kind {
        case .audio: return 0.85
        case .video: return 0.88
        }
    }

    /// Final filename (if completed).
    var fileName: String? { fileURL?.lastPathComponent }

    /// Best label to display: known title > filename > raw URL.
    var displayTitle: String {
        if let t = metadata?.title, !t.isEmpty { return t }
        return fileName ?? url
    }

    /// Thumbnail to paint. Inferred from the YouTube identifier, thus available
    /// from job creation — without waiting for any network response.
    var thumbnailURL: String? {
        YouTubeLink.thumbnailURL(for: url) ?? metadata?.thumbnailURL
    }
}
