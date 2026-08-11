// TBD — To Be Downloaded. Copyright (C) 2026 Elior Pommier.
// Licensed under the GNU AGPL v3 or later. See LICENSE and NOTICE.
import Foundation
import CryptoKit
import AppKit

/// Updates the app itself from the project's GitHub releases.
///
/// ## Security model
///
/// The app is not notarized (no Apple developer account), so macOS provides
/// NO guarantee about what we download. The guarantee comes from here:
///
/// 1. **Mandatory Ed25519 signature.** The archive must be signed by Elior's
///    private key; only their public key (`AppConfig.updatePublicKey`),
///    compiled in the binary, can validate it. A compromised GitHub repo,
///    hostile mirror, or TLS interceptor cannot produce a valid signature.
/// 2. **Verified BEFORE any extraction.** The archive is not opened until
///    its signature is validated: the decompressor is never exposed to
///    unauthenticated data.
/// 3. **Nothing is ever executed from the release.** No install script,
///    post-install, or shell. We extract with `/usr/bin/ditto` (arguments
///    passed as array) and replace a folder.
/// 4. **Constrained content.** The archive must contain exactly one `.app`,
///    with the same bundle identifier as ours and the version announced by
///    the release. Anything else is rejected.
/// 5. **No privilege escalation.** If the app folder is not writable,
///    we abandon gracefully — never prompt for admin password,
///    never install elsewhere.
/// 6. **HTTPS only**, GitHub hosts, and never redirect to anything other than
///    an asset from the requested release.
@MainActor
final class AppUpdater: ObservableObject {

    enum Status: Equatable {
        case idle
        case checking
        case downloading(Double)
        case verifying
        case upToDate
        /// Installed on disk: it will start on next launch.
        case ready(String)
        case failed(String)
        /// Update impossible in this context (dev build, read-only folder, etc.).
        /// Not an error, just a fact.
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

    /// Why this context forbids automatic updates, if applicable.
    ///
    /// The "development build" safeguard is essential: without it, running
    /// the local build would replace `build/…/TBD.app` with the published
    /// release, destroying the binary being tested.
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

    // MARK: - Update Cycle

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
        // Already installed and waiting to relaunch: do not re-download.
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
            // No release published (or private repo from here): it's not a failure,
            // there is simply nothing newer.
            status = .upToDate
        } catch {
            status = .failed(error.localizedDescription)
        }
        cleanUpWorkDirectory()
    }

    /// Relaunch on the installed version. The LAN server must be stopped first
    /// (the caller handles it): otherwise the new instance would find the port
    /// still occupied by this one.
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

    // MARK: - Download

    /// Dedicated work folder, systematically cleaned: the archive and extracted
    /// bundle never linger in a shared folder.
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

    /// Track progress of a `URLSession.download`: the archive weighs ~100 MB,
    /// an indeterminate bar would be annoying.
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

    // MARK: - Verification

    /// Ed25519 on the archive's raw bytes. Memory-mapped reading: do not load
    /// 100 MB into RAM to verify.
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
        // Current key or backup key: either is enough.
        guard keys.contains(where: { $0.isValidSignature(sigData, for: contents) }) else {
            throw UpdateError.badSignature
        }
    }

    /// Extract the archive (already authenticated) and verify it contains exactly
    /// one app, ours, at the announced version.
    ///
    /// `ditto` rather than `unzip`: it preserves permissions, extended
    /// attributes, and the ad-hoc signature of the bundle, which `unzip`
    /// destroys.
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

        // Info.plist read as raw data structure: do NOT open the bundle (no
        // code loading, even indirect).
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

    /// Atomic swap of the running bundle.
    ///
    /// Safe for the current process: on POSIX, the old bundle stays alive as
    /// long as it is mapped, so we keep running on the old version until next
    /// launch.
    private static func replaceRunningBundle(with staged: URL) throws {
        let current = Bundle.main.bundleURL
        do {
            _ = try FileManager.default.replaceItemAt(current, withItemAt: staged)
        } catch {
            throw UpdateError.installFailed(error.localizedDescription)
        }
    }

    // MARK: - Versions

    /// Compare `1.2.10` and `1.2.9` as integers, component by component.
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
