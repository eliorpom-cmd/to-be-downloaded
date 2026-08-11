// TBD — To Be Downloaded. Copyright (C) 2026 Elior Pommier.
// Licensed under the GNU AGPL v3 or later. See LICENSE and NOTICE.
import Foundation
import CryptoKit

extension Notification.Name {
    /// The effective yt-dlp binary has changed: the engine must rebuild.
    static let engineBinaryDidChange = Notification.Name("engineBinaryDidChange")
}

/// yt-dlp release channel.
///
/// YouTube changes its anti-bot measures continuously. A fix lands in `nightly`
/// in hours, in `stable` in days to weeks — hence the value of leaving the
/// choice.
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

    /// GitHub repository that publishes this channel.
    var repository: String {
        switch self {
        case .stable:  return "yt-dlp/yt-dlp"
        case .nightly: return "yt-dlp/yt-dlp-nightly-builds"
        }
    }
}

/// Keeps the yt-dlp used by the app up to date.
///
/// The binary shipped in the `.app` is only a **bootstrap**: it guarantees the
/// app works offline right after install, asking nothing of the user. But it is
/// never replaced in place — writing to `Contents/Resources` would invalidate
/// the bundle's signature, and `/Applications` is not always writable. The
/// actually-executed version thus lives in `Application Support/<App>/bin`,
/// which the app can replace at will.
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

    /// universal2 asset (x86_64 + arm64) of yt-dlp releases, already ad-hoc
    /// signed at source — essential: on Apple Silicon, an executable without a
    /// valid signature won't start at all.
    private static let assetName = "yt-dlp_macos"
    private static let checksumsName = "SHA2-256SUMS"
    /// One check per day is enough: yt-dlp does not release more frequently on
    /// stable, and nightly stays good for several days.
    private static let checkInterval: TimeInterval = 24 * 3600

    @Published private(set) var status: Status = .idle
    @Published private(set) var installedVersion: String?
    @Published private(set) var availableVersion: String?
    @Published private(set) var lastCheck: Date?

    /// True when the executed copy comes from Application Support (so updated
    /// at least once) and not from the bundle.
    var usesManagedCopy: Bool { BinaryLocator.hasManagedYtDlp }

    /// Channel the installed copy comes from. May differ from the chosen channel
    /// until the next check happens — hence its display in settings: a nightly
    /// binary under a "Stable" setting must be visible, not guessed.
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

    // MARK: - Reading installed version

    func refreshInstalledVersion() async {
        guard let url = try? BinaryLocator.effectiveYtDlp() else {
            installedVersion = nil
            return
        }
        installedVersion = await version(of: url)
    }

    /// `yt-dlp --version`, cached as long as the file does not change: the
    /// binary is a PyInstaller bundle, starting it costs ~1 s.
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

    // MARK: - Update

    /// Check the channel and install if a newer version exists.
    /// - Parameter userInitiated: `true` bypasses the 24-hour interval and
    ///   the "check automatically" setting.
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

            // A channel change forces reinstall: switching from nightly to stable
            // is a downgrade, which version comparison would refuse on its own.
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
            // The engine still points to the old path: it must rewire.
            NotificationCenter.default.post(name: .engineBinaryDidChange, object: nil)
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    /// Called when the user changes channel in settings.
    func channelDidChange() {
        availableVersion = nil
        Task { await checkForUpdate(userInitiated: true) }
    }

    // MARK: - Diagnosis

    /// Recognizes failures that betray an outdated yt-dlp facing a new YouTube
    /// measure — the only cases where suggesting an update makes sense. A
    /// "video unavailable" or private URL does not.
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

    // MARK: - GitHub Release

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
        request.setValue("\(AppConfig.shortName)/\(AppConfig.version)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20
        // HTTP cache would return a stale release right after a release.
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

    /// Download the asset and verify its SHA-256 against the release's checksum
    /// file. The goal is not to protect from a compromised GitHub (both files
    /// come from the same source) but to never install a binary truncated by a
    /// network break.
    private static func downloadVerifiedBinary(_ release: Release) async throws -> URL {
        let (temp, response) = try await URLSession.shared.download(from: release.asset)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            try? FileManager.default.removeItem(at: temp)
            throw UpdateError.http(http.statusCode)
        }

        // `download(from:)` destroys its temp file on return: move it
        // immediately.
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

    /// Lines like `<hash>  yt-dlp_macos`.
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

    /// Install the downloaded binary in the managed folder after running it
    /// once. Replacement is atomic and safe during an ongoing download: on POSIX,
    /// an already-running process keeps the old inode open.
    private static func install(_ downloaded: URL) async throws -> String {
        let fm = FileManager.default
        let destination = BinaryLocator.managedYtDlp
        try fm.createDirectory(at: BinaryLocator.managedDirectory, withIntermediateDirectories: true)

        try fm.setAttributes([.posixPermissions: NSNumber(value: 0o755)], ofItemAtPath: downloaded.path)
        // URLSession doesn't apply quarantine, but a security profile or
        // antivirus might: remove it as a precaution.
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

    // MARK: - Version comparison

    /// yt-dlp versions are dated: `2026.07.04`, and `2026.07.23.234303` for
    /// nightly. Component-by-component comparison as integers — lexicographic
    /// order would fail on `2026.7.4` vs `2026.07.23`.
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
