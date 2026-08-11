// TBD — To Be Downloaded. Copyright (C) 2026 Elior Pommier.
// Licensed under the GNU AGPL v3 or later. See LICENSE and NOTICE.
import Foundation
import CryptoKit

/// Installs and updates FFmpeg, which the app does not ship with.
///
/// **Why this file exists.** The static build we shipped was compiled with
/// `--enable-nonfree`: its own `ffmpeg -L` replies "not legally redistributable".
/// GPL is the only license that permits redistribution of FFmpeg's GPL parts,
/// and it withdraws that permission as soon as you link incompatible code to it —
/// so no license covered the combined binary anymore, and no license in this
/// repository could do anything about it. Downloading it from whoever has the
/// right to distribute it solves the problem at its root, and saves 86 MB of
/// app size in the process.
///
/// The mechanism mirrors `EngineUpdater`: nothing is ever written into the
/// bundle (it would break its signature, and `/Applications` is not always
/// writable), everything lives in `Application Support/TBD/bin`.
@MainActor
final class FFmpegInstaller: ObservableObject {

    enum Status: Equatable {
        case idle
        case checking
        /// Cumulative fraction across BOTH archives (ffmpeg then ffprobe).
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

    /// Is FFmpeg usable right now? This property decides whether the app can
    /// download anything — without it, yt-dlp can neither mux streams nor
    /// extract audio.
    var isInstalled: Bool { BinaryLocator.hasManagedFFmpeg }

    /// One check per day is more than enough: FFmpeg releases a few versions
    /// per year, whereas yt-dlp chases YouTube changes constantly.
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
        // Version stored at install time: re-reading it by launching the binary
        // on startup would cost a subprocess for nothing.
        if BinaryLocator.hasManagedFFmpeg {
            installedVersion = store.string(forKey: Key.installedVersion)
        }
    }

    // MARK: - Entry points

    /// First launch: install FFmpeg if missing, do nothing otherwise.
    /// This is the only download the app triggers without being asked —
    /// without FFmpeg, it cannot do anything at all.
    func installIfMissing() async {
        guard !isInstalled, !status.isBusy else { return }
        await run(force: true)
    }

    // MARK: - Using an FFmpeg that is already on the machine

    /// Where a Mac keeps an FFmpeg somebody installed themselves.
    ///
    /// Not read from `PATH`: a launched app inherits a minimal environment,
    /// not the shell's, so `PATH` here would say almost nothing about what
    /// the person has. These four cover Homebrew on both architectures and
    /// MacPorts, and anything else is one file picker away.
    static let commonLocations: [URL] = [
        "/opt/homebrew/bin/ffmpeg",
        "/usr/local/bin/ffmpeg",
        "/opt/local/bin/ffmpeg",
        "/usr/bin/ffmpeg",
    ].map { URL(fileURLWithPath: $0) }

    /// First of those that has both executables. `ffprobe` is not optional:
    /// yt-dlp probes streams with it before asking ffmpeg to assemble them,
    /// so half an install is no install.
    static func detectExisting() -> URL? {
        commonLocations.first { isUsablePair(at: $0) }
    }

    static func isUsablePair(at ffmpeg: URL) -> Bool {
        let fm = FileManager.default
        let ffprobe = ffmpeg.deletingLastPathComponent().appendingPathComponent("ffprobe")
        return fm.isExecutableFile(atPath: ffmpeg.path)
            && fm.isExecutableFile(atPath: ffprobe.path)
    }

    /// Point the app at an existing FFmpeg instead of downloading a second
    /// copy of it.
    ///
    /// Symlinks rather than copies, for two reasons: 80 MB duplicated for
    /// nothing, and a copy freezes at today's version while a link keeps
    /// following whatever `brew upgrade` does. If the person later removes
    /// theirs, the link dangles, `hasManagedFFmpeg` goes false, and the app
    /// says FFmpeg is missing — which is exactly true.
    @discardableResult
    func useExisting(at ffmpeg: URL) async -> Bool {
        guard !status.isBusy else { return false }
        let ffprobe = ffmpeg.deletingLastPathComponent().appendingPathComponent("ffprobe")
        guard Self.isUsablePair(at: ffmpeg) else {
            status = .failed("No ffprobe next to that ffmpeg. Both are needed, "
                             + "and they normally sit in the same folder.")
            return false
        }

        status = .installing
        // Run it before trusting it: a file with the right name and the
        // executable bit is not proof of a working FFmpeg.
        guard let version = await Self.probeVersion(of: ffmpeg) else {
            status = .failed("That file did not answer to `ffmpeg -version`.")
            return false
        }

        let fm = FileManager.default
        do {
            try fm.createDirectory(at: BinaryLocator.managedDirectory,
                                   withIntermediateDirectories: true)
            for (link, target) in [(BinaryLocator.managedFFmpeg, ffmpeg),
                                   (BinaryLocator.managedFFprobe, ffprobe)] {
                // removeItem, not a fileExists check: a DANGLING symlink left
                // by a previous link is invisible to fileExists and would make
                // createSymbolicLink fail.
                try? fm.removeItem(at: link)
                try fm.createSymbolicLink(at: link, withDestinationURL: target)
            }
        } catch {
            status = .failed(error.localizedDescription)
            return false
        }

        installedVersion = version
        store.set(version, forKey: Key.installedVersion)
        status = .installed(version)
        NotificationCenter.default.post(name: .engineBinaryDidChange, object: nil)
        return true
    }

    /// Is the FFmpeg in use one of ours or one of theirs? Settings says so:
    /// "check for updates" means nothing for a symlink to Homebrew.
    var usesExternalFFmpeg: Bool {
        (try? FileManager.default.destinationOfSymbolicLink(
            atPath: BinaryLocator.managedFFmpeg.path)) != nil
    }

    /// Check for version, then install if a newer one exists.
    /// - Parameter userInitiated: `true` bypasses the 24-hour interval.
    func checkForUpdate(userInitiated: Bool) async {
        guard !status.isBusy else { return }
        // Someone else's FFmpeg is not ours to update. Whoever installed it —
        // Homebrew, MacPorts, by hand — updates it.
        guard !usesExternalFFmpeg else { return }
        if !userInitiated {
            guard isInstalled else { return }
            // Same switch as yt-dlp. One setting governs both components,
            // because "keep the app working" is one decision, not two.
            guard AppSettings.shared.autoUpdateEngine else { return }
            if let lastCheck, Date().timeIntervalSince(lastCheck) < Self.checkInterval { return }
        }
        await run(force: false)
    }

    /// Stop using the machine's FFmpeg and fetch our own copy instead.
    func installOwnCopy() async {
        guard !status.isBusy else { return }
        await run(force: true)
    }

    /// Re-read the actually installed version by querying the binary.
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

    // MARK: - Flow

    private func run(force: Bool) async {
        status = .checking
        do {
            // Single resolution serves both components: they are published
            // together under the same versioned folder.
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
            // The engine holds a path that did not exist yet: it must rebuild,
            // or the app stays stuck until the next launch.
            NotificationCenter.default.post(name: .engineBinaryDidChange, object: nil)
        } catch {
            status = .failed(error.localizedDescription)
        }
        Self.cleanUpWorkDirectory()
    }

    // MARK: - Latest version resolution

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
                return "No published checksum for \(name), so it will not be installed."
            case .unpackFailed(let detail):
                return "The FFmpeg archive could not be unpacked: \(detail)"
            case .missingBinary(let name):
                return "The archive did not contain \(name)."
            case .unusableBinary(let detail):
                return "The downloaded FFmpeg would not run: \(detail)"
            }
        }
    }

    /// Follow the 307 "latest" **without downloading it**: the redirect response
    /// already carries the versioned path, so the available version. A request
    /// of a few bytes replaces 28 MB.
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

    /// The versioned folder is named `<timestamp>_<version>`, for example
    /// `1783011502_8.1.2`. Failing that, we return the folder as-is rather than
    /// nothing: it serves as an identity to know if something changed.
    private static func version(from archive: URL) -> String {
        let directory = archive.deletingLastPathComponent().lastPathComponent
        if let underscore = directory.firstIndex(of: "_") {
            return String(directory[directory.index(after: underscore)...])
        }
        return directory
    }

    /// Prevent `URLSession` from following the redirect: it's the redirect
    /// itself we want to read, not what it points to.
    private final class RedirectBlocker: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest) async -> URLRequest? { nil }
    }

    // MARK: - Download

    private static var workDirectory: URL {
        AppConfig.supportDirectory.appendingPathComponent("ffmpeg-install", isDirectory: true)
    }

    private static func cleanUpWorkDirectory() {
        try? FileManager.default.removeItem(at: workDirectory)
    }

    /// Download an archive and verify its published SHA-256 alongside it.
    ///
    /// This checksum comes from the same host as the archive: so it protects
    /// only against truncated transfers, not a compromised server. The
    /// verification that truly matters is the Developer ID signature, done
    /// after extraction.
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

        // `download(from:)` destroys its temp file on return.
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

    /// File `<archive>.sha256`, in format `<hash>  <name>`.
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

    /// 28 MB per archive: an indeterminate bar would raise doubt that anything
    /// is happening, precisely when the app still cannot do anything.
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

    /// Extract, authenticate, test, then install. In that order: nothing is
    /// placed in the managed folder before being verified AND having started once.
    private static func install(_ archives: [String: URL]) async throws -> String {
        let fm = FileManager.default
        let unpacked = workDirectory.appendingPathComponent("unpacked", isDirectory: true)
        try? fm.removeItem(at: unpacked)
        try fm.createDirectory(at: unpacked, withIntermediateDirectories: true)

        var verified: [String: URL] = [:]

        for component in AppConfig.FFmpegSource.components {
            guard let zip = archives[component] else { throw InstallError.missingBinary(component) }

            // `ditto` rather than `unzip`: it preserves permissions, extended
            // attributes, and signature — and it's the signature we are about to
            // verify.
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

            // THE verification that matters. A compromised host can serve an
            // archive and the checksum that goes with it; it cannot sign on
            // behalf of an Apple team whose key it does not hold.
            try CodeSignature.verifyDeveloperID(
                at: binary, teamIdentifier: AppConfig.FFmpegSource.signingTeam)

            try fm.setAttributes([.posixPermissions: NSNumber(value: 0o755)],
                                 ofItemAtPath: binary.path)
            BinaryLocator.stripQuarantine(at: binary)
            verified[component] = binary
        }

        // Dry run before replacing anything: a binary that won't start (wrong
        // architecture, missing dependency) must be rejected here, not
        // discovered on first download.
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
            // A symlink left by "use the FFmpeg I already have" must go FIRST.
            // `fileExists` and `replaceItemAt` both follow symlinks, so writing
            // over one would land on the file it points at — someone's Homebrew
            // install, replaced without asking.
            if (try? fm.destinationOfSymbolicLink(atPath: destination.path)) != nil {
                try? fm.removeItem(at: destination)
            }
            // Atomic replacement, safe during an ongoing download: on POSIX, an
            // already-running process keeps its inode.
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

    /// First line: `ffmpeg version 8.1.2-https://www.martin-riedl.de …`.
    /// The build's original suffix is stripped, but not internal dashes —
    /// a snapshot is called `N-125610-g312c830916` and must stay readable as-is.
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
