import Foundation
import SwiftUI
import AppKit

/// Orchestration partagée (UI native ET, plus tard, serveur HTTP).
/// Détient la file de jobs et pilote le moteur.
@MainActor
final class DownloadManager: ObservableObject {

    @Published private(set) var jobs: [DownloadJob] = [] {
        didSet { updateDockBadge() }
    }
    /// Erreur de configuration au démarrage (binaire manquant, etc.).
    @Published private(set) var setupError: String?

    private var engine: DownloadEngine?
    private var running: [UUID: DownloadEngine.Running] = [:]
    /// Anime la barre pendant l'assemblage ; s'arrête dès qu'aucun job n'y est.
    private var mergeTicker: Task<Void, Never>?

    /// Bibliothèque persistante alimentée à chaque téléchargement réussi.
    let library: LibraryStore

    init(library: LibraryStore = LibraryStore()) {
        self.library = library
        buildEngine()

        // Arrête tous les subprocess yt-dlp à la fermeture de l'app (évite les orphelins).
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.terminateAll() }
        }

        // yt-dlp vient d'être mis à jour : le moteur pointe encore sur l'ancien
        // chemin. Les téléchargements en vol ne sont pas touchés (ils gardent
        // leur inode), seuls les suivants prennent la nouvelle version.
        NotificationCenter.default.addObserver(
            forName: .engineBinaryDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reconfigure() }
        }
    }

    /// (Re)construit le moteur à partir des réglages courants (dossier de sortie).
    /// Appelé au démarrage et après un changement de dossier dans les Réglages.
    func reconfigure() { buildEngine() }

    private func buildEngine() {
        do {
            // Copie mise à jour si elle existe, amorce du bundle sinon.
            let ytDlp = try BinaryLocator.effectiveYtDlp()
            let ffmpeg = try BinaryLocator.url(for: AppConfig.ffmpegBinaryName)
            // ffprobe vit dans le même dossier ; on s'assure qu'il est exécutable.
            _ = try? BinaryLocator.url(for: "ffprobe")

            // Bundle CA combiné (Mozilla + trousseau système macOS) généré au
            // démarrage : gère les intercepteurs TLS locaux (Qustodio, AV, VPN…).
            let trustBundle = TrustStore.prepareBundle(
                shippedCACert: BinaryLocator.resourceInBin("cacert.pem"))

            engine = DownloadEngine(config: .init(
                ytDlp: ytDlp,
                ffmpegDirectory: ffmpeg.deletingLastPathComponent(),
                outputDirectory: AppSettings.shared.outputDirectory,
                trustBundle: trustBundle
            ))
            setupError = nil
        } catch {
            setupError = error.localizedDescription
        }
    }

    var isReady: Bool { engine != nil }

    /// Nombre de téléchargements qui occupent encore le moteur (badge Dock / menu-bar).
    var activeCount: Int {
        jobs.filter { $0.state.isActive }.count
    }

    /// Jobs de la session encore en vol, les plus récents d'abord.
    var activeJobs: [DownloadJob] {
        jobs.filter { $0.state.isActive }
    }

    private func updateDockBadge() {
        let n = activeCount
        NSApp.dockTile.badgeLabel = n > 0 ? "\(n)" : nil
    }

    /// Termine tous les téléchargements en cours (fermeture de l'app).
    func terminateAll() {
        for run in running.values { run.cancel() }
    }

    /// Démarre un nouveau téléchargement. Renvoie l'id du job (nil si refusé).
    @discardableResult
    func startDownload(urlString: String, format: DownloadFormat) -> UUID? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let engine else { return nil }

        let job = DownloadJob(url: trimmed, format: format)
        jobs.insert(job, at: 0)

        // Titre et chaîne, en deux temps : oEmbed répond en quelques centaines
        // de millisecondes, yt-dlp en quelques secondes. Sans le premier, la
        // ligne restait anonyme pendant tout le début du téléchargement.
        // (La vignette, elle, se déduit de l'URL — cf. `DownloadJob.thumbnailURL`.)
        let jobID = job.id
        Task { [weak self] in
            guard let quick = await MediaMetadata.oEmbed(for: trimmed) else { return }
            self?.apply(quick, to: jobID, overwrite: false)
        }
        Task { [weak self] in
            guard let meta = await engine.fetchMetadata(url: trimmed) else { return }
            self?.apply(meta, to: jobID, overwrite: true)
        }

        do {
            let run = try engine.start(url: trimmed, format: format)
            running[job.id] = run
            observe(run, jobID: job.id)
        } catch {
            update(job.id) {
                $0.state = .failed
                $0.errorMessage = error.localizedDescription
            }
        }
        return job.id
    }

    /// Enregistre des métadonnées sur un job.
    ///
    /// La vignette est FIGÉE sur celle déduite de l'identifiant YouTube quand
    /// elle existe : les deux sources en proposent des variantes différentes,
    /// et en changer d'URL relancerait un chargement — l'avatar clignoterait
    /// une fois le téléchargement déjà lancé.
    private func apply(_ metadata: MediaMetadata, to jobID: UUID, overwrite: Bool) {
        update(jobID) { job in
            guard overwrite || job.metadata == nil else { return }
            var merged = metadata
            merged.thumbnailURL = YouTubeLink.thumbnailURL(for: job.url)
                ?? job.metadata?.thumbnailURL ?? metadata.thumbnailURL
            job.metadata = merged
        }
    }

    /// Aperçu (titre/chaîne/durée/miniature) sans démarrer de téléchargement.
    /// Utilisé par la barre d'aperçu de l'UI et l'endpoint /api/metadata.
    func fetchMetadata(urlString: String) async -> MediaMetadata? {
        guard let engine else { return nil }
        return await engine.fetchMetadata(url: urlString)
    }

    // MARK: - Accès pour le serveur HTTP (données Sendable)

    /// Instantané JSON de tous les jobs.
    func snapshot() -> [JobDTO] { jobs.map(JobDTO.init) }

    /// URL du fichier fini d'un job terminé, sinon nil.
    func fileURL(forJobID id: UUID) -> URL? {
        guard let job = jobs.first(where: { $0.id == id }), job.state == .completed else { return nil }
        return job.fileURL
    }

    func cancel(_ jobID: UUID) {
        running[jobID]?.cancel()
        update(jobID) { if $0.state.isActive { $0.state = .cancelled } }
    }

    /// Suspend le process yt-dlp. Le `.part` reste en place, la reprise
    /// repart de l'octet courant.
    func pause(_ jobID: UUID) {
        guard let run = running[jobID],
              let job = jobs.first(where: { $0.id == jobID }),
              job.state == .downloading || job.state == .queued
        else { return }
        if run.pause() {
            update(jobID) { $0.state = .paused }
        }
    }

    func resume(_ jobID: UUID) {
        guard let run = running[jobID],
              let job = jobs.first(where: { $0.id == jobID }), job.state == .paused
        else { return }
        if run.resume() {
            update(jobID) { $0.state = .downloading }
        }
    }

    /// Bascule pause/reprise depuis un seul bouton de la capsule.
    func togglePause(_ jobID: UUID) {
        guard let job = jobs.first(where: { $0.id == jobID }) else { return }
        job.state == .paused ? resume(jobID) : pause(jobID)
    }

    func removeCompleted() {
        jobs.removeAll { $0.state == .completed || $0.state == .failed || $0.state == .cancelled }
    }

    /// Supprime un job unique (annule d'abord s'il tourne encore).
    func remove(_ jobID: UUID) {
        running[jobID]?.cancel()
        running[jobID] = nil
        jobs.removeAll { $0.id == jobID }
    }

    /// Relance un téléchargement échoué/annulé avec la même URL et le même format.
    @discardableResult
    func retry(_ jobID: UUID) -> UUID? {
        guard let job = jobs.first(where: { $0.id == jobID }) else { return nil }
        return startDownload(urlString: job.url, format: job.format)
    }

    // MARK: - Privé

    private func observe(_ run: DownloadEngine.Running, jobID: UUID) {
        Task { [weak self] in
            guard let self else { return }
            for await event in run.events {
                switch event {
                case .progress(let p):
                    self.update(jobID) { job in
                        // Ne pas écraser une pause : yt-dlp peut avoir émis une
                        // dernière ligne de progression avant de se suspendre.
                        if job.state != .cancelled && job.state != .paused { job.state = .downloading }
                        job.progress = p
                        Self.advance(&job, with: p)
                    }
                case .postProcessing:
                    self.update(jobID) { job in
                        guard job.state != .cancelled else { return }
                        job.state = .merging
                        job.overallProgress = max(job.overallProgress, job.postProcessingFloor)
                        if job.mergeStartedAt == nil { job.mergeStartedAt = Date() }
                    }
                    self.startMergeTicker()
                case .completed(let url):
                    let size = url.flatMap {
                        (try? $0.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
                    }
                    self.update(jobID) {
                        if $0.state != .cancelled {
                            $0.state = .completed
                            $0.fileURL = url
                            $0.overallProgress = 1
                            if let size { $0.fileSize = Int64(size) }
                        }
                    }
                    if let job = self.jobs.first(where: { $0.id == jobID }), job.state == .completed {
                        if let url { self.library.add(job: job, fileURL: url) }
                        Notifier.shared.downloadFinished(title: job.displayTitle, fileURL: url)
                    }
                case .failed(let message):
                    self.update(jobID) {
                        if $0.state != .cancelled {
                            $0.state = .failed
                            $0.errorMessage = message
                        }
                    }
                }
            }
            self.running[jobID] = nil
        }
    }

    // MARK: - Progression globale

    /// Projette la progression du flux courant sur la barre unique, sans jamais
    /// reculer. Un changement de nom de fichier signale le passage au flux
    /// suivant (image → son).
    private static func advance(_ job: inout DownloadJob, with progress: DownloadProgress) {
        if let file = progress.filename, file != job.currentStreamFile {
            if job.currentStreamFile != nil { job.streamIndex += 1 }
            job.currentStreamFile = file
        }
        let span = DownloadJob.phaseSpan(streamIndex: job.streamIndex, kind: job.format.kind)
        let within = progress.fraction ?? 0
        let mapped = span.lowerBound + within * (span.upperBound - span.lowerBound)
        job.overallProgress = max(job.overallProgress, mapped)
    }

    /// Fait avancer la barre pendant l'assemblage ffmpeg, dont on ne peut pas
    /// mesurer l'avancement : approche asymptotique du but — vite au début, de
    /// plus en plus lentement, sans jamais atteindre 100 % avant la fin réelle.
    /// C'est la convention pour une attente de durée inconnue.
    private func startMergeTicker() {
        guard mergeTicker == nil else { return }
        mergeTicker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard let self else { return }
                let merging = self.jobs.filter { $0.state == .merging }
                if merging.isEmpty {
                    self.mergeTicker = nil
                    return
                }
                for job in merging {
                    guard let started = job.mergeStartedAt else { continue }
                    let elapsed = Date().timeIntervalSince(started)
                    let floor = job.postProcessingFloor
                    // τ = 5 s : ~63 % du chemin restant parcouru en 5 s.
                    let eased = 1 - exp(-elapsed / 5)
                    let target = floor + (0.995 - floor) * eased
                    self.update(job.id) { $0.overallProgress = max($0.overallProgress, target) }
                }
            }
        }
    }

    private func update(_ jobID: UUID, _ mutate: (inout DownloadJob) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        mutate(&jobs[index])
    }
}
