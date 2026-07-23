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

    init() {
        buildEngine()

        // Arrête tous les subprocess yt-dlp à la fermeture de l'app (évite les orphelins).
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.terminateAll() }
        }
    }

    /// (Re)construit le moteur à partir des réglages courants (dossier de sortie).
    /// Appelé au démarrage et après un changement de dossier dans les Réglages.
    func reconfigure() { buildEngine() }

    private func buildEngine() {
        do {
            let ytDlp = try BinaryLocator.url(for: AppConfig.ytDlpBinaryName)
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

    /// Nombre de téléchargements en cours ou en file (badge Dock / menu-bar).
    var activeCount: Int {
        jobs.filter { $0.state == .downloading || $0.state == .queued }.count
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

        // Récupère titre/chaîne/miniature en parallèle : la ligne affiche un vrai
        // titre au lieu de l'URL brute, sans bloquer le démarrage du download.
        let jobID = job.id
        Task { [weak self] in
            guard let meta = await engine.fetchMetadata(url: trimmed) else { return }
            self?.update(jobID) { if $0.metadata == nil { $0.metadata = meta } }
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
        update(jobID) { if $0.state == .downloading || $0.state == .queued { $0.state = .cancelled } }
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
                    self.update(jobID) {
                        if $0.state != .cancelled { $0.state = .downloading }
                        $0.progress = p
                    }
                case .completed(let url):
                    let size = url.flatMap {
                        (try? $0.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
                    }
                    self.update(jobID) {
                        if $0.state != .cancelled {
                            $0.state = .completed
                            $0.fileURL = url
                            if let size { $0.fileSize = Int64(size) }
                        }
                    }
                    if let job = self.jobs.first(where: { $0.id == jobID }), job.state == .completed {
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

    private func update(_ jobID: UUID, _ mutate: (inout DownloadJob) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        mutate(&jobs[index])
    }
}
