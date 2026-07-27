import Foundation
import CryptoKit

extension Notification.Name {
    /// Le binaire yt-dlp effectif a changé : le moteur doit être reconstruit.
    static let engineBinaryDidChange = Notification.Name("engineBinaryDidChange")
}

/// Canal de publication yt-dlp.
///
/// YouTube change ses parades anti-bot en continu. Un correctif atterrit dans
/// `nightly` en quelques heures, dans `stable` en quelques jours à semaines —
/// d'où l'intérêt de laisser le choix.
enum UpdateChannel: String, CaseIterable, Identifiable, Sendable {
    case stable, nightly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .stable:  return "Stable"
        case .nightly: return "Nightly"
        }
    }

    var detail: String {
        switch self {
        case .stable:  return "Official releases, every few weeks"
        case .nightly: return "Same-day fixes when YouTube changes"
        }
    }

    /// Dépôt GitHub qui publie ce canal.
    var repository: String {
        switch self {
        case .stable:  return "yt-dlp/yt-dlp"
        case .nightly: return "yt-dlp/yt-dlp-nightly-builds"
        }
    }
}

/// Maintient à jour le yt-dlp utilisé par l'app.
///
/// Le binaire livré dans le `.app` n'est qu'une **amorce** : elle garantit que
/// l'app fonctionne hors ligne dès l'installation, sans rien demander à
/// l'utilisateur. Mais on ne le remplace jamais sur place — écrire dans
/// `Contents/Resources` invaliderait la signature du bundle, et `/Applications`
/// n'est pas toujours accessible en écriture. La version réellement exécutée
/// vit donc dans `Application Support/<App>/bin`, que l'app remplace à volonté.
@MainActor
final class EngineUpdater: ObservableObject {

    enum Status: Equatable {
        case idle
        case checking
        case downloading
        case upToDate
        case installed(String)
        case failed(String)

        var isBusy: Bool { self == .checking || self == .downloading }
    }

    /// Asset universal2 (x86_64 + arm64) des releases yt-dlp, déjà signé en
    /// ad-hoc à la source — indispensable : sur Apple Silicon, un exécutable
    /// sans signature valide ne démarre pas du tout.
    private static let assetName = "yt-dlp_macos"
    private static let checksumsName = "SHA2-256SUMS"
    /// Une vérification par jour suffit : yt-dlp ne publie pas plus souvent
    /// côté stable, et le nightly reste bon plusieurs jours.
    private static let checkInterval: TimeInterval = 24 * 3600

    @Published private(set) var status: Status = .idle
    @Published private(set) var installedVersion: String?
    @Published private(set) var availableVersion: String?
    @Published private(set) var lastCheck: Date?

    /// Vrai quand la copie exécutée vient d'Application Support (donc mise à
    /// jour au moins une fois) et non du bundle.
    var usesManagedCopy: Bool { BinaryLocator.hasManagedYtDlp }

    /// Canal d'où provient la copie installée. Peut différer du canal choisi
    /// tant que le prochain contrôle n'a pas eu lieu — d'où son affichage dans
    /// les réglages : un binaire nightly sous un réglage « Stable » doit se
    /// voir, pas se deviner.
    var installedChannel: UpdateChannel? {
        guard BinaryLocator.hasManagedYtDlp else { return nil }
        return UpdateChannel(rawValue: store.string(forKey: Key.installedChannel) ?? "")
    }

    private let store = UserDefaults.standard
    private enum Key {
        static let lastCheck = "ytDlpLastCheck"
        static let installedChannel = "ytDlpInstalledChannel"
        static let versionCache = "ytDlpVersionCache"
    }

    init() {
        if let stamp = store.object(forKey: Key.lastCheck) as? Double, stamp > 0 {
            lastCheck = Date(timeIntervalSince1970: stamp)
        }
    }

    // MARK: - Lecture de la version installée

    func refreshInstalledVersion() async {
        guard let url = try? BinaryLocator.effectiveYtDlp() else {
            installedVersion = nil
            return
        }
        installedVersion = await version(of: url)
    }

    /// `yt-dlp --version`, mémorisé tant que le fichier ne change pas : le
    /// binaire est un bundle PyInstaller, son démarrage coûte ~1 s.
    private func version(of url: URL) async -> String? {
        let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate?.timeIntervalSince1970 ?? 0
        let signature = "\(url.path)|\(Int(mtime))"

        if let cache = store.dictionary(forKey: Key.versionCache) as? [String: String],
           let cached = cache[signature] {
            return cached
        }

        guard let result = try? await ProcessRunner.run(executable: url, arguments: ["--version"]),
              result.exitCode == 0
        else { return nil }

        let value = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        store.set([signature: value], forKey: Key.versionCache)
        return value
    }

    // MARK: - Mise à jour

    /// Vérifie le canal et installe si une version plus récente existe.
    /// - Parameter userInitiated: `true` court-circuite l'intervalle de 24 h et
    ///   le réglage « check automatically ».
    func checkForUpdate(userInitiated: Bool) async {
        let channel = AppSettings.shared.updateChannel

        if !userInitiated {
            guard AppSettings.shared.autoUpdateEngine else { return }
            if let lastCheck, Date().timeIntervalSince(lastCheck) < Self.checkInterval { return }
        }
        guard !status.isBusy else { return }

        if installedVersion == nil { await refreshInstalledVersion() }

        status = .checking
        do {
            let release = try await Self.latestRelease(channel: channel)
            availableVersion = release.version
            let now = Date()
            lastCheck = now
            store.set(now.timeIntervalSince1970, forKey: Key.lastCheck)

            // Un changement de canal force la réinstallation : repasser de
            // nightly à stable est un downgrade, que la comparaison de version
            // refuserait toute seule.
            let channelChanged = store.string(forKey: Key.installedChannel) != channel.rawValue
                && BinaryLocator.hasManagedYtDlp
            let needsInstall = channelChanged
                || installedVersion == nil
                || Self.isNewer(release.version, than: installedVersion!)

            guard needsInstall else {
                status = .upToDate
                return
            }

            status = .downloading
            let downloaded = try await Self.downloadVerifiedBinary(release)
            let version = try await Self.install(downloaded)

            store.set(channel.rawValue, forKey: Key.installedChannel)
            installedVersion = version
            status = .installed(version)
            // Le moteur pointe encore sur l'ancien chemin : il doit se recâbler.
            NotificationCenter.default.post(name: .engineBinaryDidChange, object: nil)
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    /// Appelé quand l'utilisateur change de canal dans les réglages.
    func channelDidChange() {
        availableVersion = nil
        Task { await checkForUpdate(userInitiated: true) }
    }

    // MARK: - Diagnostic

    /// Reconnaît les échecs qui trahissent un yt-dlp dépassé par une nouvelle
    /// parade YouTube — les seuls cas où proposer une mise à jour a du sens.
    /// Un « video unavailable » ou une URL privée n'en font pas partie.
    private static let breakageMarkers = [
        "sign in to confirm",
        "not a bot",
        "nsig extraction failed",
        "signature extraction failed",
        "failed to decrypt",
        "unable to extract",
        "player response",
        "requested format is not available",
        "precondition check failed",
        "http error 403",
        "please update",
        "confirm your age",
    ]

    static func suggestsUpdate(_ message: String) -> Bool {
        let lower = message.lowercased()
        return breakageMarkers.contains { lower.contains($0) }
    }

    // MARK: - Release GitHub

    private struct Release: Sendable {
        let version: String
        let asset: URL
        let checksums: URL?
    }

    private struct ReleaseDTO: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: URL
        }
        let tag_name: String
        let assets: [Asset]
    }

    private enum UpdateError: LocalizedError {
        case http(Int)
        case assetMissing
        case checksumMismatch
        case unusableBinary(String)

        var errorDescription: String? {
            switch self {
            case .http(let code):
                return "GitHub answered \(code)."
            case .assetMissing:
                return "This release has no macOS build."
            case .checksumMismatch:
                return "The download was corrupted (checksum mismatch)."
            case .unusableBinary(let detail):
                return "The downloaded engine would not run: \(detail)"
            }
        }
    }

    private static func latestRelease(channel: UpdateChannel) async throws -> Release {
        let endpoint = URL(string: "https://api.github.com/repos/\(channel.repository)/releases/latest")!
        var request = URLRequest(url: endpoint)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("\(AppConfig.displayName)/\(AppConfig.version)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20
        // Le cache HTTP renverrait une release périmée juste après une sortie.
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw UpdateError.http(0) }
        guard http.statusCode == 200 else { throw UpdateError.http(http.statusCode) }

        let dto = try JSONDecoder().decode(ReleaseDTO.self, from: data)
        guard let asset = dto.assets.first(where: { $0.name == assetName }),
              AppConfig.isTrustedUpdateURL(asset.browser_download_url)
        else { throw UpdateError.assetMissing }
        return Release(
            version: dto.tag_name,
            asset: asset.browser_download_url,
            checksums: dto.assets.first(where: { $0.name == checksumsName })?.browser_download_url
        )
    }

    /// Télécharge l'asset et vérifie son SHA-256 contre le fichier de sommes de
    /// la release. Le but n'est pas de se protéger d'un GitHub compromis (les
    /// deux fichiers viennent de la même source) mais de ne jamais installer un
    /// binaire tronqué par une coupure réseau.
    private static func downloadVerifiedBinary(_ release: Release) async throws -> URL {
        let (temp, response) = try await URLSession.shared.download(from: release.asset)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            try? FileManager.default.removeItem(at: temp)
            throw UpdateError.http(http.statusCode)
        }

        // `download(from:)` détruit son fichier temporaire dès le retour : on le
        // déplace tout de suite.
        let staged = FileManager.default.temporaryDirectory
            .appendingPathComponent("yt-dlp-\(UUID().uuidString)")
        try FileManager.default.moveItem(at: temp, to: staged)

        if let sums = release.checksums,
           let expected = try? await expectedHash(from: sums) {
            let actual = try sha256(of: staged)
            guard actual.caseInsensitiveCompare(expected) == .orderedSame else {
                try? FileManager.default.removeItem(at: staged)
                throw UpdateError.checksumMismatch
            }
        }
        return staged
    }

    /// Lignes du type `<hash>  yt-dlp_macos`.
    private static func expectedHash(from url: URL) async throws -> String? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        let (data, _) = try await URLSession.shared.data(for: request)
        let text = String(decoding: data, as: UTF8.self)
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            if parts.count >= 2, parts.last.map(String.init) == assetName {
                return String(parts[0])
            }
        }
        return nil
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

    /// Installe le binaire téléchargé dans le dossier géré, après l'avoir
    /// réellement exécuté une fois. Le remplacement est atomique et sans danger
    /// pour un téléchargement en cours : sous POSIX, le process déjà lancé garde
    /// l'ancien inode ouvert.
    private static func install(_ downloaded: URL) async throws -> String {
        let fm = FileManager.default
        let destination = BinaryLocator.managedYtDlp
        try fm.createDirectory(at: BinaryLocator.managedDirectory, withIntermediateDirectories: true)

        try fm.setAttributes([.posixPermissions: NSNumber(value: 0o755)], ofItemAtPath: downloaded.path)
        // URLSession ne pose pas la quarantaine, mais un profil de sécurité ou
        // un antivirus peuvent le faire : on la retire par précaution.
        BinaryLocator.stripQuarantine(at: downloaded)

        let probe = try await ProcessRunner.run(executable: downloaded, arguments: ["--version"])
        let version = probe.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard probe.exitCode == 0, !version.isEmpty else {
            try? fm.removeItem(at: downloaded)
            let detail = probe.stderr
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: "\n").last.map(String.init) ?? "exit \(probe.exitCode)"
            throw UpdateError.unusableBinary(detail)
        }

        if fm.fileExists(atPath: destination.path) {
            _ = try fm.replaceItemAt(destination, withItemAt: downloaded)
        } else {
            try fm.moveItem(at: downloaded, to: destination)
        }
        try? fm.setAttributes([.posixPermissions: NSNumber(value: 0o755)],
                              ofItemAtPath: destination.path)
        return version
    }

    // MARK: - Comparaison de versions

    /// Les versions yt-dlp sont datées : `2026.07.04`, et `2026.07.23.234303`
    /// pour un nightly. Comparaison composante par composante, en entiers —
    /// l'ordre lexicographique se tromperait sur `2026.7.4` vs `2026.07.23`.
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
