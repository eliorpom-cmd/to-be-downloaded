// TBD — To Be Downloaded. Copyright (C) 2026 Elior Pommier.
// Licensed under the GNU AGPL v3 or later. See LICENSE and NOTICE.
import Foundation
import Darwin

/// Events emitted during a download.
enum DownloadEvent: Sendable {
    case progress(DownloadProgress)
    /// yt-dlp finished downloading and is starting ffmpeg post-processing
    /// (video+audio merge, MP3 extraction, container fixup).
    case postProcessing
    /// Seconds of a clip written so far. With a range, yt-dlp hands the
    /// download to FFmpeg and its own progress stays silent: FFmpeg's
    /// `time=` is the only measure there is.
    case clipProgress(seconds: Double)
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
        /// Passed to EVERY yt-dlp call (metadata, playlist, download): the
        /// JavaScript runtimes and the cache folder. Without them on the
        /// metadata call, the preview and the download would see different
        /// formats.
        var commonArguments: [String] = []
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
        ///
        /// The FFmpeg yt-dlp started is stopped too: for a clip, FFmpeg is
        /// the one downloading, and stopping only its parent left it running.
        @discardableResult
        func pause() -> Bool {
            guard process.isRunning else { return false }
            Self.signalDescendants(of: process.processIdentifier, SIGSTOP)
            return process.suspend()
        }

        @discardableResult
        func resume() -> Bool {
            guard process.isRunning else { return false }
            let resumed = process.resume()
            Self.signalDescendants(of: process.processIdentifier, SIGCONT)
            return resumed
        }

        func cancel() {
            guard process.isRunning else { return }
            // A suspended process won't handle SIGTERM: wake it up
            // first, or it will stay alive indefinitely.
            Self.signalDescendants(of: process.processIdentifier, SIGCONT)
            process.resume()
            // Children first: once yt-dlp is gone, its FFmpeg would be
            // orphaned and keep writing a file nobody wants.
            Self.signalDescendants(of: process.processIdentifier, SIGTERM)
            process.terminate()
        }

        /// Sends a signal to every process below `pid` (FFmpeg, ffprobe).
        static func signalDescendants(of pid: pid_t, _ signal: Int32) {
            for child in children(of: pid) {
                signalDescendants(of: child, signal)
                kill(child, signal)
            }
        }

        private static func children(of pid: pid_t) -> [pid_t] {
            // A fixed buffer: asked with a nil buffer, this call answers with
            // a number unrelated to the children (checked on macOS 27). The
            // result is the number of pids written. yt-dlp has one or two.
            var pids = [pid_t](repeating: 0, count: 64)
            let filled = pids.withUnsafeMutableBytes { buffer in
                proc_listchildpids(pid, buffer.baseAddress, Int32(buffer.count))
            }
            guard filled > 0 else { return [] }
            return Array(pids.prefix(Int(filled))).filter { $0 > 0 }
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
    func start(url: String, format: DownloadFormat, range: ClipRange? = nil,
               jobID: UUID) throws -> Running {
        try FileManager.default.createDirectory(
            at: config.outputDirectory, withIntermediateDirectories: true)

        // yt-dlp writes the final path (after post-processing) to this file.
        let resultFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("dl-\(UUID().uuidString).path")

        let workDir = Self.partialDirectory(for: jobID)
        try? FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = config.ytDlp
        process.arguments = Self.downloadArguments(
            url: url, format: format, range: range, config: config,
            resultFile: resultFile, workDir: workDir)

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

        let args = config.commonArguments + [
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

        let args = config.commonArguments + [
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

    /// Every argument of a download, in order. Static and free of side
    /// effects so that tests can read exactly what yt-dlp would receive.
    static func downloadArguments(url: String, format: DownloadFormat, range: ClipRange?,
                                  config: Config, resultFile: URL, workDir: URL) -> [String] {
        let pattern = range.map {
            FilenameTemplate.inserting(suffix: $0.filenameSuffix, into: config.outputPattern)
        } ?? config.outputPattern

        var args: [String] = config.commonArguments + [
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
            "-o", pattern,
        ]

        if let range {
            // Only the range is fetched: FFmpeg asks YouTube for those bytes
            // (plus the way back to the previous keyframe), never the file.
            args += ["--download-sections", range.sectionArgument]
        }

        switch format.kind {
        case .video:
            args += videoSelector(quality: format.videoQuality, trimmed: range != nil)
            args += ["--merge-output-format", "mp4"]

            if range != nil {
                args += ["--downloader-args", "ffmpeg_o:" + clipEncoderArguments(
                    quality: format.videoQuality).joined(separator: " ")]
            }

            // Not on a clip: yt-dlp would embed the subtitles of the whole
            // video, with times that no longer match the cut.
            if format.subtitles, range == nil {
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
            // On a clip, never the muxed fallback `b`: FFmpeg's ranged request
            // on a muxed stream is refused by YouTube (HTTP 403).
            switch format.audioFormat {
            case .mp3:
                args += [
                    "-f", range == nil ? "ba/b" : "ba",
                    "-x",
                    "--audio-format", "mp3",
                    "--audio-quality", "\(format.audioBitrate.rawValue)K",
                ]
            case .m4a:
                // Prefers the original AAC track: `--audio-format m4a` then
                // just remuxes it without re-encoding — faster and no generation
                // loss.
                args += [
                    "-f", range == nil ? "ba[ext=m4a]/ba/b" : "ba[ext=m4a]/ba",
                    "-x",
                    "--audio-format", "m4a",
                ]
            }
        }

        // `--` then the URL last: protects against URLs starting with '-'.
        args += ["--", url]
        return args
    }

    /// `-f` and `-S` for a video.
    ///
    /// Preference order: first the requested resolution, THEN the H.264/AAC
    /// codec. Without this codec preference, YouTube readily serves AV1,
    /// which QuickTime cannot decode on most Macs: the file arrives complete
    /// and refuses to open. In H.264 it plays everywhere, including Preview
    /// and on iPhone. Beyond 1080p, YouTube no longer offers H.264: we fall
    /// back to VP9/AV1, which require a player like IINA or VLC.
    ///
    /// `trimmed`: separate video and audio streams only (DASH). The muxed
    /// fallbacks (`b…`) can pick format 18, on which FFmpeg's ranged request
    /// gets HTTP 403.
    static func videoSelector(quality: VideoQuality, trimmed: Bool) -> [String] {
        if quality == .max {
            // "Best" means the highest resolution: we don't drop down to
            // 1080p for H.264. At equal resolution, however, H.264 comes first.
            return ["-f", trimmed ? "bv*+ba" : "bv*+ba/b",
                    "-S", "res,vcodec:h264,acodec:aac,ext:mp4:m4a"]
        }
        let h = quality.rawValue
        // The codec is filtered IN the selector, not just sorted: with a
        // simple `-S`, yt-dlp selected the muxed HLS stream (heavier,
        // fragmented) over the DASH pair avc1 + m4a.
        var choices = [
            "bv*[vcodec^=avc1][height<=\(h)]+ba[acodec^=mp4a]",
            "bv*[height<=\(h)]+ba",
        ]
        choices += trimmed ? ["bv*+ba"] : ["b[height<=\(h)]", "bv*+ba/b"]
        return ["-f", choices.joined(separator: "/"), "-S", "res:\(h),ext:mp4:m4a"]
    }

    /// Bitrate of a clip's picture, in kilobits per second.
    ///
    /// About two to three times what YouTube itself uses at each height:
    /// the hardware encoder is less efficient than YouTube's, and a second
    /// generation needs headroom to look the same. Higher only wastes disk.
    static func clipVideoKilobits(for quality: VideoQuality) -> Int {
        switch quality {
        case .p360:  return 1_500
        case .p480:  return 2_500
        case .p720:  return 5_000
        case .p1080: return 8_000
        case .max:   return 24_000
        }
    }

    /// FFmpeg output arguments for a clip: re-encode the picture with Apple's
    /// hardware encoder so the cut lands on the exact frame asked for.
    ///
    /// A plain copy can only start on a keyframe, up to a couple of seconds
    /// early, which looks like a bug to someone who placed a handle precisely.
    /// VideoToolbox re-encodes a few minutes of 1080p in seconds on Apple
    /// silicon. The bitrate is high so the second encode is not visible, and
    /// the picture is forced to 8-bit 4:2:0, the only input H.264 hardware
    /// takes (YouTube's HDR streams are 10-bit). The audio is copied.
    static func clipEncoderArguments(quality: VideoQuality) -> [String] {
        let kilobits = clipVideoKilobits(for: quality)
        return [
            "-c:v", "h264_videotoolbox",
            "-b:v", "\(kilobits)k",
            "-pix_fmt", "yuv420p",
            "-tag:v", "avc1",
            "-c:a", "copy",
        ]
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
        if line.hasPrefix("frame=") || line.hasPrefix("size=") {
            if let seconds = FFmpegProgress.time(in: line) {
                continuation.yield(.clipProgress(seconds: seconds))
            }
            return
        }
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
        // `\r` ends a line too: FFmpeg rewrites its progress line in place
        // with carriage returns and only prints `\n` at the very end.
        while let breakIndex = buffer.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
            let lineData = buffer[buffer.startIndex..<breakIndex]
            buffer.removeSubrange(buffer.startIndex...breakIndex)
            let line = String(decoding: lineData, as: UTF8.self)
            if !line.isEmpty { lines.append(line) }
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
