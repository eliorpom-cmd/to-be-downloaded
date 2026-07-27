import Foundation

/// Événements émis pendant un téléchargement.
enum DownloadEvent: Sendable {
    case progress(DownloadProgress)
    /// yt-dlp a fini de télécharger et lance un post-traitement ffmpeg
    /// (fusion vidéo+audio, extraction MP3, fixup conteneur).
    case postProcessing
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
        /// Motif `-o` complet, extension comprise.
        var outputPattern: String = "%(title)s.%(ext)s"
        /// Langues de sous-titres à incruster, par ordre de préférence.
        var subtitleLanguages: [String] = ["en"]
    }

    /// Un téléchargement en cours ; permet la pause, la reprise et l'annulation.
    final class Running: @unchecked Sendable {
        private let process: Process
        let events: AsyncStream<DownloadEvent>

        init(process: Process, events: AsyncStream<DownloadEvent>) {
            self.process = process
            self.events = events
        }

        /// Suspend yt-dlp (SIGSTOP). Le fichier `.part` reste sur place et la
        /// reprise repart de l'octet courant ; si le serveur a coupé la
        /// connexion entre-temps, yt-dlp reprend le transfert de lui-même
        /// (`--continue` est actif par défaut).
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
            // Un process suspendu ne traiterait pas SIGTERM : on le réveille
            // d'abord, sinon il resterait en vie indéfiniment.
            process.resume()
            process.terminate()
        }
    }

    let config: Config

    init(config: Config) {
        self.config = config
    }

    /// Démarre un téléchargement et renvoie un handle diffusant les événements.
    ///
    /// `jobID` détermine le dossier de travail, qui SURVIT à la fermeture de
    /// l'app : c'est ce qui permet à un téléchargement interrompu de repartir
    /// de l'octet où il s'était arrêté au lancement suivant, plutôt que de
    /// zéro. Il n'est effacé qu'en cas de succès ou d'annulation explicite.
    func start(url: String, format: DownloadFormat, jobID: UUID) throws -> Running {
        try FileManager.default.createDirectory(
            at: config.outputDirectory, withIntermediateDirectories: true)

        // yt-dlp écrit le chemin final (après post-traitement) dans ce fichier.
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
                // Succès : les fichiers partiels n'ont plus lieu d'être.
                try? FileManager.default.removeItem(at: workDir)
            } else {
                // Échec ou fermeture de l'app : on GARDE le `.part`, sinon la
                // reprise repartirait de zéro. Le ménage se fait au lancement
                // suivant pour les dossiers dont plus aucun job ne dépend.
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

    // MARK: - Fichiers partiels

    /// Dossier de travail d'un job. Sous Application Support et non dans
    /// `/tmp` : macOS y fait le ménage tout seul, et un téléchargement de
    /// plusieurs heures y perdrait ses fragments.
    static func partialDirectory(for jobID: UUID) -> URL {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support")
        return support
            .appendingPathComponent(AppConfig.displayName, isDirectory: true)
            .appendingPathComponent("partials", isDirectory: true)
            .appendingPathComponent(jobID.uuidString, isDirectory: true)
    }

    /// Supprime les dossiers partiels dont aucun job ne dépend plus.
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

    /// Liste les vidéos d'une playlist, sans extraire aucune d'entre elles.
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
            // Pas de `--restrict-filenames` : il remplaçait les espaces par des
            // soulignés et amputait les accents, d'où des noms illisibles. Sans
            // lui, yt-dlp ne remplace que ce que le système interdit vraiment.
            "--progress",       // force la progression même si --print active --quiet
            "--no-simulate",    // --print-to-file impliquerait sinon une simulation
            "--progress-template", Self.progressTemplate,
            "--print-to-file", "after_move:filepath", resultFile.path,
            // Fichiers partiels dans le dossier de travail, fichier final dans ~/Downloads.
            "-P", "home:\(config.outputDirectory.path)",
            "-P", "temp:\(workDir.path)",
            "-o", config.outputPattern,
        ]

        switch format.kind {
        case .video:
            // Ordre de préférence : d'abord la résolution demandée, PUIS le
            // codec H.264/AAC.
            //
            // Sans cette préférence de codec, YouTube sert volontiers de l'AV1,
            // que QuickTime ne sait pas décoder sur la plupart des Mac : le
            // fichier arrive complet et refuse de s'ouvrir. En H.264 il se lit
            // partout, y compris dans Aperçu et sur iPhone.
            //
            // Au-delà de 1080p, YouTube ne propose plus de H.264 : on retombe
            // alors sur VP9/AV1, qui demandent un lecteur comme IINA ou VLC.
            if format.videoQuality == .max {
                // « Best » veut dire la meilleure définition : on ne redescend
                // pas en 1080p pour du H.264. À définition égale en revanche,
                // H.264 passe devant.
                args += ["-f", "bv*+ba/b"]
                args += ["-S", "res,vcodec:h264,acodec:aac,ext:mp4:m4a"]
            } else {
                let h = format.videoQuality.rawValue
                // Le codec est filtré DANS le sélecteur, pas seulement trié :
                // avec un simple `-S`, yt-dlp retenait le flux HLS muxé (plus
                // lourd, fragmenté) plutôt que la paire DASH avc1 + m4a.
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
                // Incrustés dans le MP4 (piste `mov_text`), pas déposés en
                // fichiers `.srt` à côté : une piste qu'on active dans le
                // lecteur est plus utile qu'un fichier de plus dans le dossier.
                args += [
                    "--embed-subs",
                    "--write-subs",
                    "--write-auto-subs",   // à défaut de sous-titres écrits, ceux générés
                    "--sub-langs", config.subtitleLanguages.joined(separator: ","),
                    // Sans quoi yt-dlp laisse aussi les `.vtt` sur le disque.
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
                // Piste AAC d'origine préférée : `--audio-format m4a` se
                // contente alors de la remuxer, sans ré-encodage — plus rapide
                // et sans perte de génération.
                args += [
                    "-f", "ba[ext=m4a]/ba/b",
                    "-x",
                    "--audio-format", "m4a",
                ]
            }
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

    /// Préfixes des post-processeurs yt-dlp qui suivent le téléchargement.
    /// Ils arrivent sur stdout sous la forme `[Merger] Merging formats into …`.
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
