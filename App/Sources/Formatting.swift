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

    static func eta(_ seconds: Double?) -> String {
        guard let seconds, seconds > 0, seconds.isFinite else { return "" }
        let total = Int(seconds)
        let m = total / 60
        let s = total % 60
        return m > 0 ? "\(m) min \(s) s left" : "\(s) s left"
    }

    /// Durée d'un média : `1:04:07` ou `4:07`.
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
