import Foundation

/// Événements émis pendant un téléchargement.
enum DownloadEvent: Sendable {
    case progress(DownloadProgress)
    case completed(fileURL: URL?)
    case failed(message: String)
}

/// Lance yt-dlp en subprocess (arguments en tableau, JAMAIS de shell) et
/// diffuse la progression parsée depuis `--progress-template`.
final class DownloadEngine: @unchecked Sendable {

    struct Config {
        let ytDlp: URL
        /// Dossier contenant ffmpeg + ffprobe (passé à --ffmpeg-location).
        let ffmpegDirectory: URL
        let outputDirectory: URL
        /// Bundle CA combiné (Mozilla + trousseau système) honoré par curl_cffi
        /// via CURL_CA_BUNDLE. Corrige "certificate verify failed" y compris
        /// derrière un intercepteur TLS (contrôle parental, antivirus, proxy).
        let trustBundle: URL?
    }

    /// Un téléchargement en cours ; permet l'annulation.
    final class Running: @unchecked Sendable {
        private let process: Process
        let events: AsyncStream<DownloadEvent>

        init(process: Process, events: AsyncStream<DownloadEvent>) {
            self.process = process
            self.events = events
        }

        func cancel() {
            if process.isRunning { process.terminate() }
        }
    }

    let config: Config

    init(config: Config) {
        self.config = config
    }

    /// Démarre un téléchargement et renvoie un handle diffusant les événements.
    func start(url: String, format: DownloadFormat) throws -> Running {
        try FileManager.default.createDirectory(
            at: config.outputDirectory, withIntermediateDirectories: true)

        // yt-dlp écrit le chemin final (après post-traitement) dans ce fichier.
        let resultFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("dl-\(UUID().uuidString).path")

        // Dossier de travail isolé : yt-dlp y écrit les fichiers partiels
        // (.part, fragments…). Nettoyé à la fin (succès, échec ou annulation),
        // ce qui évite tout résidu dans ~/Downloads.
        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Downloader-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = config.ytDlp
        process.arguments = buildArgs(url: url, format: format, resultFile: resultFile, workDir: workDir)

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
            } else {
                continuation.yield(.failed(message: Self.cleanError(errAcc.recentTail, code: code)))
            }
            try? FileManager.default.removeItem(at: resultFile)
            try? FileManager.default.removeItem(at: workDir)
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

    // MARK: - Métadonnées (aperçu, sans téléchargement)

    /// Extrait titre/chaîne/durée/miniature sans rien télécharger.
    /// Utilise `--dump-single-json --skip-download` via le même backend
    /// curl_cffi (`--impersonate chrome`) que le téléchargement.
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

    /// Environnement hérité + bundle CA combiné pour la validation SSL derrière
    /// un intercepteur TLS local (contrôle parental, antivirus, proxy).
    private func trustEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        if let ca = config.trustBundle {
            env["CURL_CA_BUNDLE"] = ca.path      // backend curl_cffi (utilisé via --impersonate)
            env["SSL_CERT_FILE"] = ca.path       // Python/urllib (fallback)
            env["REQUESTS_CA_BUNDLE"] = ca.path  // backend requests (fallback)
        }
        return env
    }

    // MARK: - Construction des arguments (aucune concaténation shell)

    private func buildArgs(url: String, format: DownloadFormat, resultFile: URL, workDir: URL) -> [String] {
        var args: [String] = [
            "--ffmpeg-location", config.ffmpegDirectory.path,
            // Route les requêtes via curl_cffi : seul backend qui honore
            // CURL_CA_BUNDLE (indispensable derrière un intercepteur TLS).
            // Bonus : réduit la détection anti-bot de YouTube.
            "--impersonate", "chrome",
            "--newline",
            "--no-colors",
            "--no-playlist",
            "--restrict-filenames",
            "--progress",       // force la progression même si --print active --quiet
            "--no-simulate",    // --print-to-file impliquerait sinon une simulation
            "--progress-template", Self.progressTemplate,
            "--print-to-file", "after_move:filepath", resultFile.path,
            // Fichiers partiels dans le dossier temporaire, fichier final dans ~/Downloads.
            "-P", "home:\(config.outputDirectory.path)",
            "-P", "temp:\(workDir.path)",
            "-o", "%(title)s.%(ext)s",
        ]

        switch format.kind {
        case .video:
            if format.videoQuality == .max {
                args += ["-f", "bv*+ba/b"]
            } else {
                let h = format.videoQuality.rawValue
                args += ["-f", "bv*[height<=\(h)]+ba/b[height<=\(h)]/bv*+ba/b"]
            }
            args += ["--merge-output-format", "mp4", "-S", "ext:mp4:m4a"]

        case .audio:
            args += [
                "-f", "ba/b",
                "-x",
                "--audio-format", "mp3",
                "--audio-quality", "\(format.audioBitrate.rawValue)K",
            ]
        }

        // `--` puis l'URL en dernier : protège contre une URL commençant par '-'.
        args += ["--", url]
        return args
    }

    /// Marqueur distinctif + champs explicites séparés par tabulation.
    static let progressMarker = "@@PROG@@\t"
    static let progressTemplate =
        "download:@@PROG@@\t" + DownloadProgress.templateFieldOrder.joined(separator: "\t")

    /// Transforme la sortie d'erreur brute de yt-dlp en message lisible.
    static func cleanError(_ raw: String, code: Int32) -> String {
        let lines = raw.split(separator: "\n").map(String.init)
        let errorLines = lines.filter { $0.contains("ERROR:") }
        var message = errorLines.isEmpty
            ? (lines.last ?? "yt-dlp failed (code \(code))")
            : errorLines.joined(separator: "\n")

        // Retire le suffixe « ; please report this issue… ».
        if let range = message.range(of: "; please report") {
            message = String(message[..<range.lowerBound])
        }
        message = message
            .replacingOccurrences(of: "ERROR: ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? "yt-dlp failed (code \(code))" : message
    }

    private static func handleLine(_ line: String, continuation: AsyncStream<DownloadEvent>.Continuation) {
        guard let range = line.range(of: progressMarker) else { return }
        let payload = String(line[range.upperBound...])
        if let progress = DownloadProgress.parse(payload) {
            continuation.yield(.progress(progress))
        }
    }
}

/// Accumule des octets et en extrait des lignes complètes (thread-safe).
/// Conserve aussi une queue de texte récent pour les messages d'erreur.
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
