import Foundation
import CryptoKit

/// Installe et met à jour FFmpeg, que l'app ne livre pas.
///
/// **Pourquoi ce fichier existe.** Le build statique qu'on embarquait était
/// compilé `--enable-nonfree` : son propre `ffmpeg -L` répond « not legally
/// redistributable ». Le GPL est la seule licence qui autorise à redistribuer
/// les parties GPL de FFmpeg, et il retire cette autorisation dès qu'on y lie du
/// code incompatible — donc plus aucune licence ne couvrait le binaire combiné,
/// et aucune licence posée sur ce dépôt n'y pouvait quoi que ce soit. Le
/// télécharger depuis chez celui qui a le droit de le distribuer résout le
/// problème à la racine, et allège l'app de 86 Mo au passage.
///
/// Le fonctionnement reprend celui d'`EngineUpdater` : rien n'est jamais écrit
/// dans le bundle (ça casserait sa signature, et `/Applications` n'est pas
/// toujours inscriptible), tout vit dans `Application Support/TBD/bin`.
@MainActor
final class FFmpegInstaller: ObservableObject {

    enum Status: Equatable {
        case idle
        case checking
        /// Fraction cumulée sur les DEUX archives (ffmpeg puis ffprobe).
        case downloading(Double)
        case installing
        case upToDate
        case installed(String)
        case failed(String)

        var isBusy: Bool {
            switch self {
            case .checking, .downloading, .installing: return true
            default: return false
            }
        }
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var installedVersion: String?
    @Published private(set) var availableVersion: String?
    @Published private(set) var lastCheck: Date?

    /// FFmpeg est-il utilisable maintenant ? C'est cette propriété qui décide si
    /// l'app peut télécharger quoi que ce soit — sans elle, yt-dlp ne peut ni
    /// assembler les flux ni extraire l'audio.
    var isInstalled: Bool { BinaryLocator.hasManagedFFmpeg }

    /// Une vérification par jour suffit largement : FFmpeg publie quelques
    /// versions par an, là où yt-dlp court après les changements de YouTube.
    private static let checkInterval: TimeInterval = 24 * 3600

    private let store = UserDefaults.standard
    private enum Key {
        static let lastCheck = "ffmpegLastCheck"
        static let installedVersion = "ffmpegInstalledVersion"
    }

    init() {
        if let stamp = store.object(forKey: Key.lastCheck) as? Double, stamp > 0 {
            lastCheck = Date(timeIntervalSince1970: stamp)
        }
        // Version mémorisée à l'installation : la relire en lançant le binaire
        // au démarrage coûterait un sous-processus pour rien.
        if BinaryLocator.hasManagedFFmpeg {
            installedVersion = store.string(forKey: Key.installedVersion)
        }
    }

    // MARK: - Points d'entrée

    /// Premier lancement : installe FFmpeg s'il manque, ne fait rien sinon.
    /// C'est le seul téléchargement que l'app déclenche sans qu'on le lui
    /// demande — sans FFmpeg, elle ne sait rien faire du tout.
    func installIfMissing() async {
        guard !isInstalled, !status.isBusy else { return }
        await run(force: true)
    }

    /// Contrôle de version, puis installation si une plus récente existe.
    /// - Parameter userInitiated: `true` court-circuite l'intervalle de 24 h.
    func checkForUpdate(userInitiated: Bool) async {
        guard !status.isBusy else { return }
        if !userInitiated {
            guard isInstalled else { return }
            if let lastCheck, Date().timeIntervalSince(lastCheck) < Self.checkInterval { return }
        }
        await run(force: false)
    }

    /// Relit la version réellement installée en interrogeant le binaire.
    func refreshInstalledVersion() async {
        guard let ffmpeg = try? BinaryLocator.effectiveFFmpeg() else {
            installedVersion = nil
            return
        }
        if let version = await Self.probeVersion(of: ffmpeg) {
            installedVersion = version
            store.set(version, forKey: Key.installedVersion)
        }
    }

    // MARK: - Déroulé

    private func run(force: Bool) async {
        status = .checking
        do {
            // Une seule résolution sert aux deux composants : ils sont publiés
            // ensemble, sous le même dossier versionné.
            let latest = try await Self.resolveLatest(component: "ffmpeg")
            availableVersion = latest.version

            let now = Date()
            lastCheck = now
            store.set(now.timeIntervalSince1970, forKey: Key.lastCheck)

            if !force, isInstalled, let installedVersion, installedVersion == latest.version {
                status = .upToDate
                return
            }

            var staged: [String: URL] = [:]
            for (index, component) in AppConfig.FFmpegSource.components.enumerated() {
                let resolved = component == "ffmpeg"
                    ? latest
                    : try await Self.resolveLatest(component: component)

                status = .downloading(Double(index) / Double(AppConfig.FFmpegSource.components.count))
                staged[component] = try await Self.downloadAndVerify(resolved) { [weak self] fraction in
                    Task { @MainActor in
                        guard let self, case .downloading = self.status else { return }
                        let count = Double(AppConfig.FFmpegSource.components.count)
                        self.status = .downloading((Double(index) + fraction) / count)
                    }
                }
            }

            status = .installing
            let version = try await Self.install(staged)

            installedVersion = version
            store.set(version, forKey: Key.installedVersion)
            status = .installed(version)
            // Le moteur tient un chemin qui n'existait pas encore : il doit se
            // reconstruire, sinon l'app reste bloquée jusqu'au prochain
            // lancement.
            NotificationCenter.default.post(name: .engineBinaryDidChange, object: nil)
        } catch {
            status = .failed(error.localizedDescription)
        }
        Self.cleanUpWorkDirectory()
    }

    // MARK: - Résolution de la dernière version

    private struct Resolved: Sendable {
        let component: String
        let archive: URL
        let version: String
    }

    private enum InstallError: LocalizedError {
        case http(Int)
        case noRedirect
        case untrustedURL
        case checksumMismatch(String)
        case checksumMissing(String)
        case unpackFailed(String)
        case missingBinary(String)
        case unusableBinary(String)

        var errorDescription: String? {
            switch self {
            case .http(let code):
                return "The FFmpeg server answered \(code)."
            case .noRedirect:
                return "The FFmpeg server did not point at a build."
            case .untrustedURL:
                return "The FFmpeg download was redirected somewhere unexpected."
            case .checksumMismatch(let name):
                return "The \(name) download was corrupted (checksum mismatch)."
            case .checksumMissing(let name):
                return "No published checksum for \(name) — refusing to install it."
            case .unpackFailed(let detail):
                return "The FFmpeg archive could not be unpacked: \(detail)"
            case .missingBinary(let name):
                return "The archive did not contain \(name)."
            case .unusableBinary(let detail):
                return "The downloaded FFmpeg would not run: \(detail)"
            }
        }
    }

    /// Suit le 307 « latest » **sans le télécharger** : la réponse de redirection
    /// porte déjà le chemin versionné, donc la version disponible. Une requête
    /// de quelques octets remplace 28 Mo.
    private static func resolveLatest(component: String) async throws -> Resolved {
        let entry = URL(string: "\(AppConfig.FFmpegSource.latestBase)/\(component).zip")!
        guard AppConfig.FFmpegSource.isTrustedURL(entry) else { throw InstallError.untrustedURL }

        var request = URLRequest(url: entry)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (_, response) = try await URLSession.shared.data(for: request, delegate: RedirectBlocker())
        guard let http = response as? HTTPURLResponse else { throw InstallError.http(0) }
        guard (300...399).contains(http.statusCode) else { throw InstallError.http(http.statusCode) }
        guard let location = http.value(forHTTPHeaderField: "Location"),
              let archive = URL(string: location, relativeTo: entry)?.absoluteURL
        else { throw InstallError.noRedirect }
        guard AppConfig.FFmpegSource.isTrustedURL(archive) else { throw InstallError.untrustedURL }

        return Resolved(component: component, archive: archive, version: version(from: archive))
    }

    /// Le dossier versionné s'appelle `<horodatage>_<version>`, par exemple
    /// `1783011502_8.1.2`. À défaut, on rend le dossier tel quel plutôt que rien :
    /// il sert d'identité pour savoir si quelque chose a changé.
    private static func version(from archive: URL) -> String {
        let directory = archive.deletingLastPathComponent().lastPathComponent
        if let underscore = directory.firstIndex(of: "_") {
            return String(directory[directory.index(after: underscore)...])
        }
        return directory
    }

    /// Empêche `URLSession` de suivre la redirection : c'est elle qu'on veut
    /// lire, pas ce qu'il y a au bout.
    private final class RedirectBlocker: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest) async -> URLRequest? { nil }
    }

    // MARK: - Téléchargement

    private static var workDirectory: URL {
        AppConfig.supportDirectory.appendingPathComponent("ffmpeg-install", isDirectory: true)
    }

    private static func cleanUpWorkDirectory() {
        try? FileManager.default.removeItem(at: workDirectory)
    }

    /// Télécharge une archive et vérifie son SHA-256 publié à côté d'elle.
    ///
    /// Cette somme vient du même hôte que l'archive : elle ne protège donc pas
    /// d'un serveur compromis, seulement d'un transfert tronqué. La vérification
    /// qui compte vraiment est la signature Developer ID, faite après extraction.
    private static func downloadAndVerify(
        _ resolved: Resolved,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: workDirectory, withIntermediateDirectories: true)

        let expected = try await publishedChecksum(for: resolved)

        let (temp, response) = try await URLSession.shared.download(
            from: resolved.archive, delegate: ProgressObserver(onProgress: onProgress))
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            try? fm.removeItem(at: temp)
            throw InstallError.http(http.statusCode)
        }

        // `download(from:)` détruit son fichier temporaire dès le retour.
        let zip = workDirectory.appendingPathComponent("\(resolved.component).zip")
        try? fm.removeItem(at: zip)
        try fm.moveItem(at: temp, to: zip)

        let actual = try sha256(of: zip)
        guard actual.caseInsensitiveCompare(expected) == .orderedSame else {
            try? fm.removeItem(at: zip)
            throw InstallError.checksumMismatch(resolved.component)
        }
        return zip
    }

    /// Fichier `<archive>.sha256`, au format `<hash>  <nom>`.
    private static func publishedChecksum(for resolved: Resolved) async throws -> String {
        let url = resolved.archive.appendingPathExtension("sha256")
        guard AppConfig.FFmpegSource.isTrustedURL(url) else { throw InstallError.untrustedURL }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw InstallError.http(http.statusCode)
        }
        let text = String(decoding: data, as: UTF8.self)
        guard let hash = text.split(separator: " ", omittingEmptySubsequences: true).first,
              hash.count == 64
        else { throw InstallError.checksumMissing(resolved.component) }
        return String(hash)
    }

    private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// 28 Mo par archive : une barre indéterminée ferait douter qu'il se passe
    /// quelque chose, au moment précis où l'app ne sait encore rien faire.
    private final class ProgressObserver: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
        private let onProgress: @Sendable (Double) -> Void

        init(onProgress: @escaping @Sendable (Double) -> Void) {
            self.onProgress = onProgress
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                        didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                        totalBytesExpectedToWrite: Int64) {
            guard totalBytesExpectedToWrite > 0 else { return }
            onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                        didFinishDownloadingTo location: URL) {}
    }

    // MARK: - Installation

    /// Extrait, authentifie, essaie, puis installe. Dans cet ordre : rien n'est
    /// posé dans le dossier géré avant d'être vérifié ET d'avoir démarré une fois.
    private static func install(_ archives: [String: URL]) async throws -> String {
        let fm = FileManager.default
        let unpacked = workDirectory.appendingPathComponent("unpacked", isDirectory: true)
        try? fm.removeItem(at: unpacked)
        try fm.createDirectory(at: unpacked, withIntermediateDirectories: true)

        var verified: [String: URL] = [:]

        for component in AppConfig.FFmpegSource.components {
            guard let zip = archives[component] else { throw InstallError.missingBinary(component) }

            // `ditto` plutôt qu'`unzip` : il préserve permissions, attributs
            // étendus et signature — et c'est la signature qu'on s'apprête à
            // vérifier.
            let result = try await ProcessRunner.run(
                executable: URL(fileURLWithPath: "/usr/bin/ditto"),
                arguments: ["-x", "-k", zip.path, unpacked.path])
            guard result.exitCode == 0 else {
                throw InstallError.unpackFailed(result.stderr
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .split(separator: "\n").last.map(String.init) ?? "ditto exit \(result.exitCode)")
            }

            let binary = unpacked.appendingPathComponent(component)
            guard fm.fileExists(atPath: binary.path) else {
                throw InstallError.missingBinary(component)
            }

            // LA vérification qui compte. Un hôte compromis peut servir une
            // archive et la somme qui va avec ; il ne peut pas signer au nom
            // d'une équipe Apple dont il n'a pas la clé.
            try CodeSignature.verifyDeveloperID(
                at: binary, teamIdentifier: AppConfig.FFmpegSource.signingTeam)

            try fm.setAttributes([.posixPermissions: NSNumber(value: 0o755)],
                                 ofItemAtPath: binary.path)
            BinaryLocator.stripQuarantine(at: binary)
            verified[component] = binary
        }

        // Essai à blanc avant de rien remplacer : un binaire qui ne démarre pas
        // (mauvaise architecture, dépendance manquante) doit être refusé ici, pas
        // découvert au premier téléchargement.
        guard let ffmpeg = verified["ffmpeg"] else { throw InstallError.missingBinary("ffmpeg") }
        let probe = try await ProcessRunner.run(executable: ffmpeg, arguments: ["-version"])
        guard probe.exitCode == 0, let version = parseVersion(probe.stdout) else {
            let detail = probe.stderr
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: "\n").last.map(String.init) ?? "exit \(probe.exitCode)"
            throw InstallError.unusableBinary(detail)
        }

        try fm.createDirectory(at: BinaryLocator.managedDirectory, withIntermediateDirectories: true)
        for (component, binary) in verified {
            let destination = BinaryLocator.managedDirectory.appendingPathComponent(component)
            // Remplacement atomique, sans danger pendant un téléchargement en
            // cours : sous POSIX, le process déjà lancé garde son inode.
            if fm.fileExists(atPath: destination.path) {
                _ = try fm.replaceItemAt(destination, withItemAt: binary)
            } else {
                try fm.moveItem(at: binary, to: destination)
            }
            try? fm.setAttributes([.posixPermissions: NSNumber(value: 0o755)],
                                  ofItemAtPath: destination.path)
        }
        return version
    }

    private static func probeVersion(of ffmpeg: URL) async -> String? {
        guard let result = try? await ProcessRunner.run(executable: ffmpeg, arguments: ["-version"]),
              result.exitCode == 0
        else { return nil }
        return parseVersion(result.stdout)
    }

    /// Première ligne : `ffmpeg version 8.1.2-https://www.martin-riedl.de …`.
    /// Le suffixe d'origine du build est retiré, mais pas les tirets internes —
    /// un snapshot s'appelle `N-125610-g312c830916` et doit rester lisible tel quel.
    static func parseVersion(_ output: String) -> String? {
        guard let line = output.split(separator: "\n").first,
              let range = line.range(of: "version ")
        else { return nil }
        var token = String(line[range.upperBound...])
            .split(separator: " ").first.map(String.init) ?? ""
        if let suffix = token.range(of: "-http") {
            token = String(token[..<suffix.lowerBound])
        }
        return token.isEmpty ? nil : token
    }
}
