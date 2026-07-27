import Foundation

/// Progression d'un téléchargement, issue de `--progress-template %(progress)j`.
/// Le dictionnaire JSON de yt-dlp peut contenir des `null` : tout est optionnel.
struct DownloadProgress: Sendable, Equatable {
    var status: String
    var downloadedBytes: Int64?
    var totalBytes: Int64?
    var speed: Double?   // octets/seconde
    var eta: Double?     // secondes restantes
    /// Fichier en cours d'écriture. Sert à repérer le passage d'un flux au
    /// suivant : une vidéo YouTube se télécharge en DEUX temps (piste vidéo,
    /// puis piste audio), et chacun repart de 0 %.
    var filename: String?

    /// Fraction téléchargée [0...1], ou nil si la taille totale est inconnue.
    var fraction: Double? {
        guard let total = totalBytes, total > 0, let done = downloadedBytes else { return nil }
        return min(1.0, Double(done) / Double(total))
    }

    /// Champs (séparés par tabulation) émis par `--progress-template`, dans
    /// l'ordre : status, downloaded_bytes, total_bytes, total_bytes_estimate,
    /// speed, eta. Les valeurs absentes valent "NA".
    static let templateFieldOrder = [
        "%(progress.status)s",
        "%(progress.downloaded_bytes)s",
        "%(progress.total_bytes)s",
        "%(progress.total_bytes_estimate)s",
        "%(progress.speed)s",
        "%(progress.eta)s",
        // En dernier : un nom de fichier peut contenir à peu près n'importe
        // quoi, on ne veut pas qu'il décale les champs suivants.
        "%(progress.filename)s",
    ]

    /// Parse la charge utile (après le marqueur) : champs séparés par tabulation.
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
