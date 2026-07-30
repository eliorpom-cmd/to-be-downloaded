import Foundation

/// Locates and prepares embedded binaries (yt-dlp, ffmpeg) in the bundle.
///
/// Binaries are copied to `Contents/Resources/bin` of the .app. On copy,
/// the executable bit can be lost: we restore it at runtime (`ensureExecutable`).
enum BinaryLocator {

    enum BinaryError: LocalizedError {
        case notFound(String)
        /// FFmpeg is not shipped with the app: it installs on first
        /// launch (see `FFmpegInstaller`). Normal case, not an anomaly —
        /// the UI treats it as an install step, not an error.
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

    /// URL of the `bin` folder in the bundle's Resources.
    static var binDirectory: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("bin", isDirectory: true)
    }

    /// Resolves the path of an embedded binary and ensures it is executable.
    /// - Parameter name: file name (e.g., "yt-dlp").
    static func url(for name: String) throws -> URL {
        // 1) Search via Bundle API (works if the file is a flat resource).
        if let url = Bundle.main.url(forResource: name, withExtension: nil, subdirectory: "bin") {
            try ensureExecutable(at: url)
            return url
        }
        // 2) Fallback: construct the path manually.
        if let dir = binDirectory {
            let url = dir.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) {
                try ensureExecutable(at: url)
                return url
            }
        }
        throw BinaryError.notFound(name)
    }

    // MARK: - Managed Copy (Hot Update)

    /// Folder of binaries that the app can replace itself.
    ///
    /// Intentionally OUTSIDE the bundle: rewriting `Contents/Resources` would
    /// break the `.app`'s signature, and `/Applications` is not always
    /// user-writable.
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

    /// yt-dlp actually executed: the updated copy if it exists, otherwise
    /// the bootstrap shipped in the bundle (which guarantees a working app
    /// right after installation, even offline).
    static func effectiveYtDlp() throws -> URL {
        if hasManagedYtDlp {
            try? ensureExecutable(at: managedYtDlp)
            return managedYtDlp
        }
        return try url(for: AppConfig.ytDlpBinaryName)
    }

    // MARK: - FFmpeg (never embedded)

    static var managedFFmpeg: URL {
        managedDirectory.appendingPathComponent(AppConfig.ffmpegBinaryName)
    }

    static var managedFFprobe: URL {
        managedDirectory.appendingPathComponent("ffprobe")
    }

    /// BOTH executables are needed: yt-dlp probes streams with ffprobe before
    /// asking ffmpeg to assemble. Having only one (interrupted install) amounts
    /// to having none.
    static var hasManagedFFmpeg: Bool {
        let fm = FileManager.default
        return fm.isExecutableFile(atPath: managedFFmpeg.path)
            && fm.isExecutableFile(atPath: managedFFprobe.path)
    }

    /// FFmpeg actually executed. Unlike yt-dlp, there is NO bootstrap in the
    /// bundle: the build we put there was not redistributable (see
    /// `FFmpegInstaller`). Until it is installed, the app says so and offers to
    /// download it.
    static func effectiveFFmpeg() throws -> URL {
        guard hasManagedFFmpeg else {
            throw BinaryError.notInstalled(AppConfig.ffmpegBinaryName)
        }
        try? ensureExecutable(at: managedFFmpeg)
        try? ensureExecutable(at: managedFFprobe)
        return managedFFmpeg
    }

    /// Path of a resource (non-executable) in `bin`, if it exists.
    static func resourceInBin(_ name: String) -> URL? {
        guard let dir = binDirectory else { return nil }
        let url = dir.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Restore the executable bit (`chmod +x`) and remove quarantine.
    static func ensureExecutable(at url: URL) throws {
        let fm = FileManager.default
        let perms = try fm.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        let current = perms?.uint16Value ?? 0
        // 0o111 = executable bits (user/group/other).
        if current & 0o111 == 0 {
            let newPerms = NSNumber(value: current | 0o755)
            try fm.setAttributes([.posixPermissions: newPerms], ofItemAtPath: url.path)
        }
        stripQuarantine(at: url)
    }

    /// Remove `com.apple.quarantine`: without notarization, an embedded binary
    /// inherits quarantine if the app was downloaded/AirDropped, which prevents
    /// its execution. Remove it so yt-dlp/ffmpeg start.
    static func stripQuarantine(at url: URL) {
        url.path.withCString { path in
            _ = removexattr(path, "com.apple.quarantine", 0)
        }
    }
}
