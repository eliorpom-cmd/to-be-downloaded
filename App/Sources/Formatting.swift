// TBD — To Be Downloaded. Copyright (C) 2026 Elior Pommier.
// Licensed under the GNU AGPL v3 or later. See LICENSE and NOTICE.
import Foundation

enum Format {
    static func bytes(_ value: Int64?) -> String {
        guard let value else { return "—" }
        return ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    static func speed(_ bytesPerSec: Double?) -> String {
        guard let bps = bytesPerSec, bps > 0 else { return "" }
        let s = ByteCountFormatter.string(fromByteCount: Int64(bps), countStyle: .file)
        return "\(s)/s"
    }

    /// Remaining time, ROUNDED to a granularity that grows with the value.
    ///
    /// yt-dlp's estimate jitters with each packet: raw, it gave "47 s",
    /// "1 min 3 s", "52 s" from one second to the next — a countdown that went
    /// backwards and changed width every frame. We quantize it like browsers do:
    /// the displayed number becomes stable and no longer claims precision it
    /// doesn't have.
    static func eta(_ seconds: Double?) -> String {
        guard let seconds, seconds > 0, seconds.isFinite, seconds < 24 * 3600 else { return "" }
        let total = Int(seconds)
        switch total {
        case ..<10:
            return "a few seconds left"
        case ..<60:
            return "\(round(total, to: 5)) s left"
        case ..<600:
            let rounded = round(total, to: 10)
            return String(format: "%d:%02d left", rounded / 60, rounded % 60)
        default:
            return "\(round(total, to: 60) / 60) min left"
        }
    }

    private static func round(_ value: Int, to step: Int) -> Int {
        max(step, ((value + step / 2) / step) * step)
    }

    /// "2 hours ago" for discrete timestamps in settings. Formatter created on
    /// the fly: `RelativeDateTimeFormatter` is not `Sendable`, so it can't be
    /// shared as `static let` under Swift 6.
    static func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    /// Duration of a media: `1:04:07` or `4:07`.
    static func duration(_ seconds: Double?) -> String {
        guard let seconds, seconds > 0, seconds.isFinite else { return "" }
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }
}
