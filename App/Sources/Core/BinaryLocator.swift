import Foundation

/// Localise et prépare les binaires embarqués (yt-dlp, ffmpeg) dans le bundle.
///
/// Les binaires sont copiés dans `Contents/Resources/bin` du .app. À la copie,
/// le bit exécutable peut être perdu : on le rétablit au runtime (`ensureExecutable`).
enum BinaryLocator {

    enum BinaryError: LocalizedError {
        case notFound(String)
        /// FFmpeg n'est pas livré avec l'app : il s'installe au premier
        /// lancement (cf. `FFmpegInstaller`). Cas normal, pas une anomalie —
        /// l'interface le traite comme une étape d'installation, pas une erreur.
        case notInstalled(String)

        var errorDescription: String? {
            switch self {
            case .notFound(let name):
                return "Binary not found in bundle: \(name)"
            case .notInstalled(let name):
                return "\(name) is not installed yet."
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

    // MARK: - Copie gérée (mise à jour à chaud)

    /// Dossier des binaires que l'app peut remplacer elle-même.
    ///
    /// Volontairement HORS du bundle : réécrire `Contents/Resources` casserait
    /// la signature du `.app`, et `/Applications` n'est pas toujours accessible
    /// en écriture à l'utilisateur.
    static var managedDirectory: URL {
        AppConfig.supportDirectory
            .appendingPathComponent("bin", isDirectory: true)
    }

    static var managedYtDlp: URL {
        managedDirectory.appendingPathComponent(AppConfig.ytDlpBinaryName)
    }

    static var hasManagedYtDlp: Bool {
        FileManager.default.isExecutableFile(atPath: managedYtDlp.path)
    }

    /// yt-dlp réellement exécuté : la copie mise à jour si elle existe, sinon
    /// l'amorce livrée dans le bundle (qui garantit une app fonctionnelle dès
    /// l'installation, même hors ligne).
    static func effectiveYtDlp() throws -> URL {
        if hasManagedYtDlp {
            try? ensureExecutable(at: managedYtDlp)
            return managedYtDlp
        }
        return try url(for: AppConfig.ytDlpBinaryName)
    }

    // MARK: - FFmpeg (jamais embarqué)

    static var managedFFmpeg: URL {
        managedDirectory.appendingPathComponent(AppConfig.ffmpegBinaryName)
    }

    static var managedFFprobe: URL {
        managedDirectory.appendingPathComponent("ffprobe")
    }

    /// Les DEUX exécutables sont nécessaires : yt-dlp sonde les flux avec
    /// ffprobe avant de demander l'assemblage à ffmpeg. N'en avoir qu'un
    /// (installation interrompue) équivaut à n'en avoir aucun.
    static var hasManagedFFmpeg: Bool {
        let fm = FileManager.default
        return fm.isExecutableFile(atPath: managedFFmpeg.path)
            && fm.isExecutableFile(atPath: managedFFprobe.path)
    }

    /// FFmpeg réellement exécuté. Contrairement à yt-dlp, il n'y a PAS d'amorce
    /// dans le bundle : le build qu'on y mettait n'était pas redistribuable
    /// (cf. `FFmpegInstaller`). Tant qu'il n'est pas installé, l'app le dit et
    /// propose de le télécharger.
    static func effectiveFFmpeg() throws -> URL {
        guard hasManagedFFmpeg else {
            throw BinaryError.notInstalled(AppConfig.ffmpegBinaryName)
        }
        try? ensureExecutable(at: managedFFmpeg)
        try? ensureExecutable(at: managedFFprobe)
        return managedFFmpeg
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
