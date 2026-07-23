import Foundation

/// Localise et prépare les binaires embarqués (yt-dlp, ffmpeg) dans le bundle.
///
/// Les binaires sont copiés dans `Contents/Resources/bin` du .app. À la copie,
/// le bit exécutable peut être perdu : on le rétablit au runtime (`ensureExecutable`).
enum BinaryLocator {

    enum BinaryError: LocalizedError {
        case notFound(String)

        var errorDescription: String? {
            switch self {
            case .notFound(let name):
                return "Binary not found in bundle: \(name)"
            }
        }
    }

    /// URL du dossier `bin` dans les Resources du bundle.
    static var binDirectory: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("bin", isDirectory: true)
    }

    /// Résout le chemin d'un binaire embarqué et garantit qu'il est exécutable.
    /// - Parameter name: nom du fichier (ex. "yt-dlp").
    static func url(for name: String) throws -> URL {
        // 1) Cherche via l'API Bundle (fonctionne si le fichier est une resource plate).
        if let url = Bundle.main.url(forResource: name, withExtension: nil, subdirectory: "bin") {
            try ensureExecutable(at: url)
            return url
        }
        // 2) Repli : construit le chemin manuellement.
        if let dir = binDirectory {
            let url = dir.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) {
                try ensureExecutable(at: url)
                return url
            }
        }
        throw BinaryError.notFound(name)
    }

    /// Chemin d'une resource (non exécutable) dans `bin`, si elle existe.
    static func resourceInBin(_ name: String) -> URL? {
        guard let dir = binDirectory else { return nil }
        let url = dir.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Rétablit le bit exécutable (`chmod +x`) et retire la quarantaine.
    static func ensureExecutable(at url: URL) throws {
        let fm = FileManager.default
        let perms = try fm.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        let current = perms?.uint16Value ?? 0
        // 0o111 = bits exécutables (user/group/other).
        if current & 0o111 == 0 {
            let newPerms = NSNumber(value: current | 0o755)
            try fm.setAttributes([.posixPermissions: newPerms], ofItemAtPath: url.path)
        }
        stripQuarantine(at: url)
    }

    /// Retire `com.apple.quarantine` : sans notarisation, un binaire embarqué
    /// hérite de la quarantaine si l'app a été téléchargée/AirDrop, ce qui
    /// empêche son exécution. On l'enlève pour que yt-dlp/ffmpeg démarrent.
    static func stripQuarantine(at url: URL) {
        url.path.withCString { path in
            _ = removexattr(path, "com.apple.quarantine", 0)
        }
    }
}
