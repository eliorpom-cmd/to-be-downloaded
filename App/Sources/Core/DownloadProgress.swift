// TBD — To Be Downloaded. Copyright (C) 2026 Elior Pommier.
// Licensed under the GNU AGPL v3 or later. See LICENSE and NOTICE.
import Foundation

/// Download progress from `--progress-template %(progress)j`.
/// yt-dlp's JSON dict may contain `null` values: everything is optional.
struct DownloadProgress: Sendable, Equatable {
    var status: String
    var downloadedBytes: Int64?
    var totalBytes: Int64?
    var speed: Double?   // bytes/second
    var eta: Double?     // seconds remaining
    /// File currently being written. Used to detect the transition from one
    /// stream to the next: a YouTube video downloads in TWO stages (video track,
    /// then audio track), and each starts from 0%.
    var filename: String?

    /// Fraction downloaded [0...1], or nil if total size is unknown.
    var fraction: Double? {
        guard let total = totalBytes, total > 0, let done = downloadedBytes else { return nil }
        return min(1.0, Double(done) / Double(total))
    }

    /// Fields (tab-separated) emitted by `--progress-template`, in
    /// order: status, downloaded_bytes, total_bytes, total_bytes_estimate,
    /// speed, eta. Missing values equal "NA".
    static let templateFieldOrder = [
        "%(progress.status)s",
        "%(progress.downloaded_bytes)s",
        "%(progress.total_bytes)s",
        "%(progress.total_bytes_estimate)s",
        "%(progress.speed)s",
        "%(progress.eta)s",
        // Last: a filename can contain pretty much anything; we don't want
        // it to offset the following fields.
        "%(progress.filename)s",
    ]

    /// Parses the payload (after the marker): fields separated by tabs.
    static func parse(_ payload: String) -> DownloadProgress? {
        let parts = payload.components(separatedBy: "\t")
        guard parts.count >= 6 else { return nil }

        func number(_ raw: String) -> Double? {
            let t = raw.trimmingCharacters(in: .whitespaces)
            if t.isEmpty || t == "NA" || t.caseInsensitiveCompare("none") == .orderedSame {
                return nil
            }
            return Double(t)
        }

        let status = parts[0].isEmpty ? "downloading" : parts[0]
        let downloaded = number(parts[1]).map { Int64($0) }
        let total = (number(parts[2]) ?? number(parts[3])).map { Int64($0) }

        let filename = parts.count > 6
            ? parts[6].trimmingCharacters(in: .whitespaces)
            : ""

        return DownloadProgress(
            status: status,
            downloadedBytes: downloaded,
            totalBytes: total,
            speed: number(parts[4]),
            eta: number(parts[5]),
            filename: (filename.isEmpty || filename == "NA") ? nil : filename
        )
    }
}
