// TBD — To Be Downloaded. Copyright (C) 2026 Elior Pommier.
// Licensed under the GNU AGPL v3 or later. See LICENSE and NOTICE.
import Foundation

/// Events emitted during a download.
enum DownloadEvent: Sendable {
    case progress(DownloadProgress)
    /// yt-dlp finished downloading and is starting ffmpeg post-processing
    /// (video+audio merge, MP3 extraction, container fixup).
    case postProcessing
    case completed(fileURL: URL?)
    case failed(message: String)
}

/// Runs yt-dlp as a subprocess (arguments as array, NEVER shell) and
/// streams parsed progress from `--progress-template`.
final class DownloadEngine: @unchecked Sendable {

    struct Config {
        let ytDlp: URL
        /// Folder containing ffmpeg + ffprobe (passed to --ffmpeg-location).
        let ffmpegDirectory: URL
        let outputDirectory: URL
        /// Combined CA bundle (Mozilla + system keychain) honored by curl_cffi
        /// via CURL_CA_BUNDLE. Fixes "certificate verify failed" even
        /// behind TLS interceptors (parental controls, antivirus, proxy).
        let trustBundle: URL?
        /// Complete `-o` pattern, extension included.
        var outputPattern: String = "%(title)s.%(ext)s"
        /// Subtitle languages to embed, by preference order.
        var subtitleLanguages: [String] = ["en"]
        /// Accept YouTube's machine transcription when the channel wrote no
        /// subtitles of its own.
        var autoSubtitles: Bool = true
    }

    /// A download in progress; allows pause, resume, and cancellation.
    final class Running: @unchecked Sendable {
        private let process: Process
        let events: AsyncStream<DownloadEvent>

        init(process: Process, events: AsyncStream<DownloadEvent>) {
            self.process = process
            self.events = events
        }

        /// Suspends yt-dlp (SIGSTOP). The `.part` file stays in place and
        /// resume restarts from the current byte; if the server closed the
        /// connection in the meantime, yt-dlp resumes the transfer on its own
        /// (`--continue` is active by default).
        @discardableResult
        func pause() -> Bool {
            guard process.isRunning else { return false }
            return process.suspend()
        }

        @discardableResult
        func resume() -> Bool {
            guard process.isRunning else { return false }
            return process.resume()
        }

        func cancel() {
            guard process.isRunning else { return }
            // A suspended process won't handle SIGTERM: wake it up
            // first, or it will stay alive indefinitely.
            process.resume()
            process.terminate()
        }
    }

    let config: Config

    init(config: Config) {
        self.config = config
    }

    /// Starts a download and returns a handle streaming events.
    ///
    /// `jobID` determines the work folder, which SURVIVES app closure:
    /// this allows an interrupted download to resume from the byte where it
    /// stopped on next launch, rather than from zero. It's only deleted on
    /// success or explicit cancellation.
    func start(url: String, format: DownloadFormat, jobID: UUID) throws -> Running {
        try FileManager.default.createDirectory(
            at: config.outputDirectory, withIntermediateDirectories: true)

        // yt-dlp writes the final path (after post-processing) to this file.
        let resultFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("dl-\(UUID().uuidString).path")

        let workDir = Self.partialDirectory(for: jobID)
        try? FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = config.ytDlp
        process.arguments = buildArgs(
            url: url, format: format, resultFile: resultFile, workDir: workDir)

        process.environment = trustEnvironment()

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        let (stream, continuation) = AsyncStream<DownloadEvent>.makeStream()

        let outAcc = LineAccumulator()
        let errAcc = LineAccumulator()

        outPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil; return }
            for line in outAcc.append(data) {
                Self.handleLine(line, continuation: continuation)
            }
        }
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil; return }
            for line in errAcc.append(data) {
                Self.handleLine(line, continuation: continuation)
            }
        }

        process.terminationHandler = { proc in
            let code = proc.terminationStatus
            if code == 0 {
                let path = (try? String(contentsOf: resultFile, encoding: .utf8))?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let fileURL = (path?.isEmpty == false) ? URL(fileURLWithPath: path!) : nil
                continuation.yield(.completed(fileURL: fileURL))
                // Success: partial files are no longer needed.
                try? FileManager.default.removeItem(at: workDir)
            } else {
                // Failure or app closure: we KEEP the `.part`, else resume would
                // restart from zero. Cleanup happens on next launch for folders
                // no job depends on anymore.
                continuation.yield(.failed(message: Self.cleanError(errAcc.recentTail, code: code)))
            }
            try? FileManager.default.removeItem(at: resultFile)
            continuation.finish()
        }

        do {
            try process.run()
        } catch {
            continuation.yield(.failed(message: "Lancement impossible : \(error.localizedDescription)"))
            continuation.finish()
        }

        return Running(process: process, events: stream)
    }

    // MARK: - Partial files

    /// Job work folder. Under Application Support, not in `/tmp`: macOS
    /// cleans it up on its own, and a download of several hours would
    /// lose its fragments there.
    static func partialDirectory(for jobID: UUID) -> URL {
        AppConfig.supportDirectory
            .appendingPathComponent("partials", isDirectory: true)
            .appendingPathComponent(jobID.uuidString, isDirectory: true)
    }

    /// Removes partial folders no job depends on anymore.
    static func prunePartials(keeping ids: Set<UUID>) {
        let root = partialDirectory(for: UUID()).deletingLastPathComponent()
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil) else { return }
        for entry in entries {
            guard let id = UUID(uuidString: entry.lastPathComponent), ids.contains(id) else {
                try? FileManager.default.removeItem(at: entry)
                continue
            }
        }
    }

    // MARK: - Metadata (preview, no download)

    /// Extracts title/channel/duration/thumbnail without downloading.
    /// Uses `--dump-single-json --skip-download` via the same
    /// curl_cffi backend (`--impersonate chrome`) as the download.
    func fetchMetadata(url: String) async -> MediaMetadata? {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let args = [
            "--impersonate", "chrome",
            "--no-playlist",
            "--skip-download",
            "--no-warnings",
            "--dump-single-json",
            "--", trimmed,
        ]

        guard let result = try? await ProcessRunner.run(
            executable: config.ytDlp, arguments: args, environment: trustEnvironment()
        ), result.exitCode == 0 else { return nil }

        return MediaMetadata.decode(from: Data(result.stdout.utf8))
    }

    /// Lists videos from a playlist, without extracting any of them.
    func fetchPlaylist(url: String) async -> Playlist? {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let args = [
            "--impersonate", "chrome",
            "--flat-playlist",
            "--skip-download",
            "--no-warnings",
            "--dump-single-json",
            "--", trimmed,
        ]

        guard let result = try? await ProcessRunner.run(
            executable: config.ytDlp, arguments: args, environment: trustEnvironment()
        ), result.exitCode == 0 else { return nil }

        return Playlist.decode(from: Data(result.stdout.utf8))
    }

    /// Inherited environment + combined CA bundle for SSL validation behind
    /// a local TLS interceptor (parental controls, antivirus, proxy).
    private func trustEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        if let ca = config.trustBundle {
            env["CURL_CA_BUNDLE"] = ca.path      // curl_cffi backend (used via --impersonate)
            env["SSL_CERT_FILE"] = ca.path       // Python/urllib (fallback)
            env["REQUESTS_CA_BUNDLE"] = ca.path  // requests backend (fallback)
        }
        return env
    }

    // MARK: - Argument building (no shell concatenation)

    private func buildArgs(url: String, format: DownloadFormat, resultFile: URL, workDir: URL) -> [String] {
        var args: [String] = [
            "--ffmpeg-location", config.ffmpegDirectory.path,
            // Routes requests via curl_cffi: only backend that honors
            // CURL_CA_BUNDLE (essential behind a TLS interceptor).
            // Bonus: reduces YouTube's anti-bot detection.
            "--impersonate", "chrome",
            "--newline",
            "--no-colors",
            "--no-playlist",
            // No `--restrict-filenames`: it replaced spaces with underscores
            // and truncated accents, resulting in unreadable names. Without it,
            // yt-dlp replaces only what the system actually forbids.
            "--progress",       // forces progress even if --print activates --quiet
            "--no-simulate",    // --print-to-file would otherwise imply a simulation
            "--progress-template", Self.progressTemplate,
            "--print-to-file", "after_move:filepath", resultFile.path,
            // Partial files in the work folder, final file in ~/Downloads.
            "-P", "home:\(config.outputDirectory.path)",
            "-P", "temp:\(workDir.path)",
            "-o", config.outputPattern,
        ]

        switch format.kind {
        case .video:
            // Preference order: first the requested resolution, THEN the
            // H.264/AAC codec.
            //
            // Without this codec preference, YouTube readily serves AV1,
            // which QuickTime cannot decode on most Macs: the file arrives
            // complete and refuses to open. In H.264 it plays everywhere,
            // including Preview and on iPhone.
            //
            // Beyond 1080p, YouTube no longer offers H.264: we fall back to
            // VP9/AV1, which require a player like IINA or VLC.
            if format.videoQuality == .max {
                // "Best" means the highest resolution: we don't drop down to
                // 1080p for H.264. At equal resolution, however, H.264 comes first.
                args += ["-f", "bv*+ba/b"]
                args += ["-S", "res,vcodec:h264,acodec:aac,ext:mp4:m4a"]
            } else {
                let h = format.videoQuality.rawValue
                // The codec is filtered IN the selector, not just sorted: with
                // a simple `-S`, yt-dlp selected the muxed HLS stream (heavier,
                // fragmented) over the DASH pair avc1 + m4a.
                args += ["-f", [
                    "bv*[vcodec^=avc1][height<=\(h)]+ba[acodec^=mp4a]",
                    "bv*[height<=\(h)]+ba",
                    "b[height<=\(h)]",
                    "bv*+ba/b",
                ].joined(separator: "/")]
                args += ["-S", "res:\(h),ext:mp4:m4a"]
            }
            args += ["--merge-output-format", "mp4"]

            if format.subtitles {
                // Embedded in the MP4 (track `mov_text`), not deposited in
                // `.srt` files alongside: a track you activate in the player
                // is more useful than an extra file in the folder.
                args += ["--embed-subs", "--write-subs"]
                // Machine transcription, only if asked for. yt-dlp prefers a
                // channel's own subtitles when both exist, so this is strictly
                // a fallback — and one worth being able to refuse, since
                // YouTube's auto captions are punctuation-free and often wrong.
                if config.autoSubtitles { args += ["--write-auto-subs"] }
                args += [
                    "--sub-langs", config.subtitleLanguages.joined(separator: ","),
                    // Otherwise yt-dlp leaves `.vtt` files on disk too.
                    "--compat-options", "no-keep-subs",
                ]
            }

        case .audio:
            switch format.audioFormat {
            case .mp3:
                args += [
                    "-f", "ba/b",
                    "-x",
                    "--audio-format", "mp3",
                    "--audio-quality", "\(format.audioBitrate.rawValue)K",
                ]
            case .m4a:
                // Prefers the original AAC track: `--audio-format m4a` then
                // just remuxes it without re-encoding — faster and no generation
                // loss.
                args += [
                    "-f", "ba[ext=m4a]/ba/b",
                    "-x",
                    "--audio-format", "m4a",
                ]
            }
        }

        // `--` then the URL last: protects against URLs starting with '-'.
        args += ["--", url]
        return args
    }

    /// Distinctive marker + explicit fields separated by tabs.
    static let progressMarker = "@@PROG@@\t"
    static let progressTemplate =
        "download:@@PROG@@\t" + DownloadProgress.templateFieldOrder.joined(separator: "\t")

    /// Transforms raw yt-dlp stderr into a readable message.
    static func cleanError(_ raw: String, code: Int32) -> String {
        let lines = raw.split(separator: "\n").map(String.init)
        let errorLines = lines.filter { $0.contains("ERROR:") }
        var message = errorLines.isEmpty
            ? (lines.last ?? "yt-dlp failed (code \(code))")
            : errorLines.joined(separator: "\n")

        // Removes the "; please report this issue…" suffix.
        if let range = message.range(of: "; please report") {
            message = String(message[..<range.lowerBound])
        }
        message = message
            .replacingOccurrences(of: "ERROR: ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? "yt-dlp failed (code \(code))" : message
    }

    /// Prefixes of yt-dlp post-processors that follow the download.
    /// They arrive on stdout as `[Merger] Merging formats into …`.
    private static let postProcessingPrefixes = [
        "[Merger]", "[ExtractAudio]", "[Fixup", "[VideoConvertor]", "[Metadata]",
    ]

    private static func handleLine(_ line: String, continuation: AsyncStream<DownloadEvent>.Continuation) {
        if let range = line.range(of: progressMarker) {
            let payload = String(line[range.upperBound...])
            if let progress = DownloadProgress.parse(payload) {
                continuation.yield(.progress(progress))
            }
            return
        }
        if postProcessingPrefixes.contains(where: line.hasPrefix) {
            continuation.yield(.postProcessing)
        }
    }
}

/// Accumulates bytes and extracts complete lines from them (thread-safe).
/// Also keeps a queue of recent text for error messages.
final class LineAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private var tail = ""

    func append(_ data: Data) -> [String] {
        lock.lock(); defer { lock.unlock() }
        buffer.append(data)

        var lines: [String] = []
        while let newlineIndex = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer[buffer.startIndex..<newlineIndex]
            buffer.removeSubrange(buffer.startIndex...newlineIndex)
            var line = String(decoding: lineData, as: UTF8.self)
            if line.hasSuffix("\r") { line.removeLast() }
            lines.append(line)
        }

        if !lines.isEmpty {
            tail = String((tail + "\n" + lines.joined(separator: "\n")).suffix(2000))
        }
        return lines
    }

    var recentTail: String {
        lock.lock(); defer { lock.unlock() }
        return tail.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
