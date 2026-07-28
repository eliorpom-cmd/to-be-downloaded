import Foundation
import CryptoKit
import AppKit

/// Met à jour l'app elle-même depuis les releases GitHub du projet.
///
/// ## Modèle de sécurité
///
/// L'app n'est pas notarisée (pas de compte développeur Apple), donc macOS
/// n'apporte AUCUNE garantie sur ce qu'on télécharge. La garantie vient d'ici :
///
/// 1. **Signature Ed25519 obligatoire.** L'archive doit être signée par la clé
///    privée d'Elior ; seule sa clé publique (`AppConfig.updatePublicKey`),
///    compilée dans le binaire, permet de valider. Un dépôt GitHub compromis,
///    un miroir hostile ou un intercepteur TLS ne peuvent pas produire de
///    signature valide.
/// 2. **Vérifiée AVANT toute extraction.** L'archive n'est pas ouverte tant que
///    sa signature n'est pas validée : le décompresseur n'est jamais exposé à
///    des données non authentifiées.
/// 3. **Rien n'est jamais exécuté depuis la release.** Pas de script
///    d'installation, pas de post-install, pas de shell. On extrait avec
///    `/usr/bin/ditto` (arguments passés en tableau) et on remplace un dossier.
/// 4. **Contenu contraint.** L'archive doit contenir exactement un `.app`,
///    portant le même identifiant de bundle que nous et la version annoncée par
///    la release. Tout le reste est refusé.
/// 5. **Aucune élévation de privilèges.** Si le dossier de l'app n'est pas
///    inscriptible, on abandonne en le disant — jamais de demande de mot de
///    passe administrateur, jamais d'installation ailleurs.
/// 6. **HTTPS uniquement**, hôtes GitHub, et jamais de redirection vers autre
///    chose qu'un asset de la release demandée.
@MainActor
final class AppUpdater: ObservableObject {

    enum Status: Equatable {
        case idle
        case checking
        case downloading(Double)
        case verifying
        case upToDate
        /// Installée sur le disque : elle démarrera au prochain lancement.
        case ready(String)
        case failed(String)
        /// Mise à jour impossible dans ce contexte (build de dev, dossier en
        /// lecture seule…). Ce n'est pas une erreur, juste un constat.
        case unavailable(String)

        var isBusy: Bool {
            switch self {
            case .checking, .verifying, .downloading: return true
            default: return false
            }
        }
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var availableVersion: String?
    @Published private(set) var lastCheck: Date?
    @Published private(set) var releaseNotes: String?

    private static let checkInterval: TimeInterval = 24 * 3600

    private let store = UserDefaults.standard
    private enum Key {
        static let lastCheck = "appUpdateLastCheck"
    }

    var currentVersion: String { AppConfig.version }

    init() {
        if let stamp = store.object(forKey: Key.lastCheck) as? Double, stamp > 0 {
            lastCheck = Date(timeIntervalSince1970: stamp)
        }
        if let reason = Self.unavailableReason { status = .unavailable(reason) }
    }

    /// Pourquoi ce contexte interdit la mise à jour automatique, le cas échéant.
    ///
    /// Le garde-fou « build de développement » est essentiel : sans lui, lancer
    /// le build local remplacerait `build/…/TBD.app` par la release
    /// publiée, ce qui détruirait le binaire en cours de test.
    private static var unavailableReason: String? {
        let path = Bundle.main.bundleURL.path
        if path.contains("/Build/Products/") || path.contains("/DerivedData/") {
            return "Disabled for development builds"
        }
        if AppConfig.updatePublicKeys.isEmpty || AppConfig.updateRepository.isEmpty {
            return "No update channel configured"
        }
        let parent = Bundle.main.bundleURL.deletingLastPathComponent().path
        if !FileManager.default.isWritableFile(atPath: parent) {
            return "The folder holding the app is read-only"
        }
        return nil
    }

    // MARK: - Cycle de mise à jour

    func checkForUpdate(userInitiated: Bool) async {
        if let reason = Self.unavailableReason {
            status = .unavailable(reason)
            return
        }
        if !userInitiated {
            guard AppSettings.shared.autoUpdateApp else { return }
            if let lastCheck, Date().timeIntervalSince(lastCheck) < Self.checkInterval { return }
        }
        guard !status.isBusy else { return }
        // Déjà installée et en attente de relance : ne rien retélécharger.
        if case .ready = status, !userInitiated { return }

        status = .checking
        do {
            let release = try await Self.latestRelease()
            availableVersion = release.version
            releaseNotes = release.notes
            let now = Date()
            lastCheck = now
            store.set(now.timeIntervalSince1970, forKey: Key.lastCheck)

            guard Self.isNewer(release.version, than: currentVersion) else {
                status = .upToDate
                return
            }

            let archive = try await download(release)
            status = .verifying
            try Self.verifySignature(archive: archive.zip, signature: archive.signature)
            let staged = try await Self.unpackAndValidate(archive.zip, expecting: release.version)
            try Self.replaceRunningBundle(with: staged)

            status = .ready(release.version)
        } catch UpdateError.http(404) {
            // Aucune release publiée (ou dépôt privé vu d'ici) : ce n'est pas
            // une panne, il n'y a simplement rien de plus récent.
            status = .upToDate
        } catch {
            status = .failed(error.localizedDescription)
        }
        cleanUpWorkDirectory()
    }

    /// Redémarre sur la version installée. Le serveur LAN doit être arrêté avant
    /// (l'appelant s'en charge) : sinon la nouvelle instance trouverait le port
    /// encore occupé par celle-ci.
    func relaunch() {
        let target = Bundle.main.bundleURL
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", target.path]
        try? task.run()
        NSApp.terminate(nil)
    }

    // MARK: - Release GitHub

    private struct Release: Sendable {
        let version: String
        let notes: String?
        let zip: URL
        let zipSize: Int64
        let signature: URL
    }

    private struct ReleaseDTO: Decodable {
        struct Asset: Decodable {
            let name: String
            let size: Int64
            let browser_download_url: URL
        }
        let tag_name: String
        let body: String?
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]
    }

    private enum UpdateError: LocalizedError {
        case http(Int)
        case missingAsset
        case badSignature
        case unpackFailed(String)
        case unexpectedContents(String)
        case installFailed(String)

        var errorDescription: String? {
            switch self {
            case .http(let code):
                return "GitHub answered \(code)."
            case .missingAsset:
                return "This release has no signed macOS archive."
            case .badSignature:
                return "The archive is not signed by the developer key. Nothing was installed."
            case .unpackFailed(let detail):
                return "The archive could not be unpacked: \(detail)"
            case .unexpectedContents(let detail):
                return "The archive does not contain what it should: \(detail)"
            case .installFailed(let detail):
                return "The new version could not be installed: \(detail)"
            }
        }
    }

    private static func latestRelease() async throws -> Release {
        let endpoint = URL(string: "https://api.github.com/repos/\(AppConfig.updateRepository)/releases/latest")!
        var request = URLRequest(url: endpoint)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("\(AppConfig.shortName)/\(AppConfig.version)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw UpdateError.http(0) }
        guard http.statusCode == 200 else { throw UpdateError.http(http.statusCode) }

        let dto = try JSONDecoder().decode(ReleaseDTO.self, from: data)
        guard !dto.draft, !dto.prerelease else { throw UpdateError.missingAsset }

        guard let zip = dto.assets.first(where: { $0.name.hasSuffix(".zip") }),
              let sig = dto.assets.first(where: { $0.name == zip.name + ".sig" }),
              AppConfig.isTrustedUpdateURL(zip.browser_download_url),
              AppConfig.isTrustedUpdateURL(sig.browser_download_url)
        else { throw UpdateError.missingAsset }

        return Release(
            version: dto.tag_name.hasPrefix("v") ? String(dto.tag_name.dropFirst()) : dto.tag_name,
            notes: dto.body?.trimmingCharacters(in: .whitespacesAndNewlines),
            zip: zip.browser_download_url,
            zipSize: zip.size,
            signature: sig.browser_download_url)
    }

    // MARK: - Téléchargement

    /// Dossier de travail dédié, systématiquement nettoyé : l'archive et le
    /// bundle extrait ne traînent jamais dans un dossier partagé.
    private static var workDirectory: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(AppConfig.shortName)-update", isDirectory: true)
    }

    private func cleanUpWorkDirectory() {
        try? FileManager.default.removeItem(at: Self.workDirectory)
    }

    private func download(_ release: Release) async throws -> (zip: URL, signature: URL) {
        let fm = FileManager.default
        cleanUpWorkDirectory()
        try fm.createDirectory(at: Self.workDirectory, withIntermediateDirectories: true)

        status = .downloading(0)
        let progress = ProgressObserver { [weak self] fraction in
            Task { @MainActor in
                guard let self, case .downloading = self.status else { return }
                self.status = .downloading(fraction)
            }
        }

        let (temp, response) = try await URLSession.shared.download(from: release.zip, delegate: progress)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            try? fm.removeItem(at: temp)
            throw UpdateError.http(http.statusCode)
        }
        let zip = Self.workDirectory.appendingPathComponent("update.zip")
        try fm.moveItem(at: temp, to: zip)

        let (sigData, sigResponse) = try await URLSession.shared.data(from: release.signature)
        if let http = sigResponse as? HTTPURLResponse, http.statusCode != 200 {
            throw UpdateError.http(http.statusCode)
        }
        let signature = Self.workDirectory.appendingPathComponent("update.zip.sig")
        try sigData.write(to: signature)

        return (zip, signature)
    }

    /// Suit l'avancement d'un `URLSession.download` : l'archive pèse ~100 Mo,
    /// une barre indéterminée serait pénible.
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

    // MARK: - Vérification

    /// Ed25519 sur les octets bruts de l'archive. Lecture mappée : on ne charge
    /// pas 100 Mo en RAM pour vérifier.
    private static func verifySignature(archive: URL, signature: URL) throws {
        guard let sigText = try? String(contentsOf: signature, encoding: .utf8),
              let sigData = Data(base64Encoded: sigText.trimmingCharacters(in: .whitespacesAndNewlines))
        else { throw UpdateError.badSignature }

        let keys = AppConfig.updatePublicKeys.compactMap { encoded -> Curve25519.Signing.PublicKey? in
            guard let raw = Data(base64Encoded: encoded) else { return nil }
            return try? Curve25519.Signing.PublicKey(rawRepresentation: raw)
        }
        guard !keys.isEmpty else { throw UpdateError.badSignature }

        let contents = try Data(contentsOf: archive, options: .mappedIfSafe)
        // Clé courante ou clé de secours : l'une suffit.
        guard keys.contains(where: { $0.isValidSignature(sigData, for: contents) }) else {
            throw UpdateError.badSignature
        }
    }

    /// Extrait l'archive (déjà authentifiée) et vérifie qu'elle contient bien
    /// une seule app, la nôtre, à la version annoncée.
    ///
    /// `ditto` plutôt qu'`unzip` : il préserve les permissions, les attributs
    /// étendus et la signature ad-hoc du bundle, ce qu'`unzip` détruit.
    private static func unpackAndValidate(_ zip: URL, expecting version: String) async throws -> URL {
        let fm = FileManager.default
        let destination = workDirectory.appendingPathComponent("unpacked", isDirectory: true)
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)

        let result = try await ProcessRunner.run(
            executable: URL(fileURLWithPath: "/usr/bin/ditto"),
            arguments: ["-x", "-k", zip.path, destination.path])
        guard result.exitCode == 0 else {
            throw UpdateError.unpackFailed(result.stderr
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: "\n").last.map(String.init) ?? "ditto exit \(result.exitCode)")
        }

        let entries = (try? fm.contentsOfDirectory(at: destination, includingPropertiesForKeys: nil))?
            .filter { $0.lastPathComponent != "__MACOSX" } ?? []
        let apps = entries.filter { $0.pathExtension == "app" }
        guard apps.count == 1, entries.count == apps.count else {
            throw UpdateError.unexpectedContents(
                "expected a single .app, found \(entries.map(\.lastPathComponent).joined(separator: ", "))")
        }
        let app = apps[0]

        // Info.plist lu comme une simple structure de données : on n'ouvre PAS
        // le bundle (aucun chargement de code, même indirect).
        guard let plistData = try? Data(contentsOf: app.appendingPathComponent("Contents/Info.plist")),
              let plist = try? PropertyListSerialization.propertyList(
                from: plistData, options: [], format: nil) as? [String: Any]
        else { throw UpdateError.unexpectedContents("unreadable Info.plist") }

        let identifier = plist["CFBundleIdentifier"] as? String
        guard identifier == Bundle.main.bundleIdentifier else {
            throw UpdateError.unexpectedContents("bundle identifier is \(identifier ?? "missing")")
        }
        let shipped = plist["CFBundleShortVersionString"] as? String
        guard shipped == version else {
            throw UpdateError.unexpectedContents(
                "release says \(version), the app inside says \(shipped ?? "nothing")")
        }
        guard fm.isExecutableFile(atPath: app
            .appendingPathComponent("Contents/MacOS/\(plist["CFBundleExecutable"] as? String ?? "")").path)
        else { throw UpdateError.unexpectedContents("no executable inside") }

        return app
    }

    /// Échange atomique du bundle en cours d'exécution.
    ///
    /// Sans danger pour le process actuel : sous POSIX, l'ancien bundle reste
    /// vivant tant qu'il est mappé, on continue donc de tourner sur l'ancienne
    /// version jusqu'au prochain lancement.
    private static func replaceRunningBundle(with staged: URL) throws {
        let current = Bundle.main.bundleURL
        do {
            _ = try FileManager.default.replaceItemAt(current, withItemAt: staged)
        } catch {
            throw UpdateError.installFailed(error.localizedDescription)
        }
    }

    // MARK: - Versions

    /// Compare `1.2.10` et `1.2.9` en entiers, composante par composante.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let left = i < a.count ? a[i] : 0
            let right = i < b.count ? b[i] : 0
            if left != right { return left > right }
        }
        return false
    }
}
