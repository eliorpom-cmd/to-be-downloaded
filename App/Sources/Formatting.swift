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

    /// Temps restant, ARRONDI à une granularité qui grandit avec la valeur.
    ///
    /// L'estimation de yt-dlp sautille à chaque paquet : brute, elle donnait
    /// « 47 s », « 1 min 3 s », « 52 s » d'une seconde à l'autre — un compte à
    /// rebours qui remonte et dont la largeur change à chaque image. On la
    /// quantifie donc, comme le font les navigateurs : le chiffre affiché
    /// devient stable et ne prétend plus à une précision qu'il n'a pas.
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

    /// « 2 hours ago », pour les horodatages discrets des réglages.
    /// Formateur créé à la volée : `RelativeDateTimeFormatter` n'est pas
    /// `Sendable`, donc impossible à partager en `static let` sous Swift 6.
    static func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
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
