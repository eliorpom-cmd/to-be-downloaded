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

    /// Jobs interrompus par une fermeture de l'app, proposés à la reprise.
    @Published private(set) var resumable: [PendingJob] = []

    /// Métadonnées déjà extraites, par identifiant vidéo, et extractions en vol.
    private var metadataCache: [String: MediaMetadata] = [:]
    private var metadataTasks: [String: Task<MediaMetadata?, Never>] = [:]

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

        // Raccourci global : traité ici et non dans une vue, pour qu'il marche
        // même quand la fenêtre est fermée — c'est tout son intérêt.
        NotificationCenter.default.addObserver(
            forName: .globalPasteAndDownload, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { _ = self?.downloadFromClipboard() }
        }

        // Même raison pour les liens venus de l'extérieur (service macOS,
        // extension de partage, schéma d'URL) : aucune fenêtre requise.
        NotificationCenter.default.addObserver(
            forName: .externalDownloadRequest, object: nil, queue: .main
        ) { [weak self] note in
            guard let link = note.userInfo?["url"] as? String else { return }
            MainActor.assumeIsolated {
                self?.startDownload(
                    urlString: link, format: AppSettings.shared.currentDefaultFormat)
            }
        }
    }

    /// Lance le lien du presse-papier avec les réglages par défaut.
    @discardableResult
    func downloadFromClipboard() -> UUID? {
        guard let copied = NSPasteboard.general.string(forType: .string),
              YouTubeLink.isValid(copied)
        else { return nil }
        return startDownload(
            urlString: copied.trimmingCharacters(in: .whitespacesAndNewlines),
            format: AppSettings.shared.currentDefaultFormat)
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

            let settings = AppSettings.shared
            engine = DownloadEngine(config: .init(
                ytDlp: ytDlp,
                ffmpegDirectory: ffmpeg.deletingLastPathComponent(),
                outputDirectory: settings.outputDirectory,
                trustBundle: trustBundle,
                outputPattern: settings.outputPattern,
                subtitleLanguages: settings.subtitleLanguages
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

    /// Badge + barre de progression sur l'icône du Dock. La fraction est la
    /// MOYENNE des téléchargements en vol : une seule barre pour un seul
    /// message, « voilà où en est le lot ».
    private func updateDockBadge() {
        let active = jobs.filter { $0.state.isActive }
        let fraction = active.isEmpty
            ? nil
            : active.reduce(0.0) { $0 + $1.overallProgress } / Double(active.count)
        DockProgress.update(fraction: fraction, badge: active.count)
    }

    /// Termine tous les téléchargements en cours (fermeture de l'app).
    func terminateAll() {
        for run in running.values { run.cancel() }
    }

    /// Met un téléchargement en file. Renvoie l'id du job (nil si refusé).
    ///
    /// « En file » et non « démarre » : au-delà de `maxConcurrent`, le job
    /// attend son tour. Lancer dix transferts de front ne va pas plus vite —
    /// la bande passante ne change pas — mais retarde le premier fichier
    /// utilisable et rend tous les temps restants mensongers.
    @discardableResult
    func startDownload(urlString: String, format: DownloadFormat, id: UUID = UUID()) -> UUID? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let engine else { return nil }

        let job = DownloadJob(url: trimmed, format: format, id: id)
        jobs.insert(job, at: 0)

        // Titre et chaîne, en deux temps : oEmbed répond en quelques centaines
        // de millisecondes, yt-dlp en quelques secondes. Sans le premier, la
        // ligne restait anonyme pendant tout le début du téléchargement.
        // (La vignette, elle, se déduit de l'URL — cf. `DownloadJob.thumbnailURL`.)
        let jobID = job.id
        Task { [weak self] in
            guard let quick = await MediaMetadata.oEmbed(for: trimmed) else { return }
            self?.apply(quick, to: jobID, overwrite: false)
            // La photo de profil de la chaîne demande une résolution à part, et
            // n'est en cache qu'à partir du deuxième téléchargement de la même
            // chaîne. Elle arrive donc APRÈS le nom, ce qui est l'ordre utile.
            guard let key = quick.channelKey, let channelURL = quick.channelURL,
                  let avatar = await ChannelAvatars.shared.avatarURL(
                    channelKey: key, channelURL: channelURL)
            else { return }
            self?.update(jobID) { $0.metadata?.channelAvatarURL = avatar }
        }
        // Passe par le cache : si l'aperçu du poids a déjà extrait cette vidéo
        // pendant que l'utilisateur hésitait, on ne relance rien.
        Task { [weak self] in
            guard let meta = await self?.fetchMetadata(urlString: trimmed) else { return }
            self?.apply(meta, to: jobID, overwrite: true)
        }

        savePending()
        pump()
        return job.id
    }

    /// Met en file toutes les vidéos choisies d'une playlist, dans l'ordre.
    func startPlaylist(_ entries: [Playlist.Entry], format: DownloadFormat) {
        // En sens inverse : `startDownload` insère en tête, donc partir de la
        // fin laisse la liste dans l'ordre de la playlist à l'écran.
        for entry in entries.reversed() {
            startDownload(urlString: entry.url, format: format)
        }
    }

    // MARK: - File d'attente

    /// Nombre de jobs qui occupent réellement le moteur.
    private var activeSlots: Int {
        jobs.filter { running[$0.id] != nil && $0.state.isActive }.count
    }

    /// Lance autant de jobs en attente que la limite l'autorise, du plus ancien
    /// au plus récent — l'ordre dans lequel ils ont été demandés.
    private func pump() {
        guard let engine else { return }
        let limit = max(1, AppSettings.shared.maxConcurrent)
        while activeSlots < limit {
            guard let index = jobs.lastIndex(where: {
                $0.state == .queued && running[$0.id] == nil
            }) else { return }
            let job = jobs[index]
            do {
                let run = try engine.start(url: job.url, format: job.format, jobID: job.id)
                running[job.id] = run
                // L'état reste `queued` : yt-dlp doit d'abord se lancer et
                // interroger YouTube, ce qui prend un temps très visible.
                // Annoncer « downloading » à cet instant afficherait 0 % et une
                // barre morte pendant tout ce temps. C'est le premier événement
                // de progression qui fera basculer l'état.
                observe(run, jobID: job.id)
            } catch {
                jobs[index].state = .failed
                jobs[index].errorMessage = error.localizedDescription
            }
        }
    }

    /// Un job en attente derrière d'autres, plutôt qu'en train de démarrer.
    func isWaiting(_ job: DownloadJob) -> Bool {
        job.state == .queued && running[job.id] == nil
    }

    // MARK: - Reprise après fermeture

    /// Ce qu'il faut pour relancer un job interrompu.
    struct PendingJob: Codable, Sendable, Identifiable, Equatable {
        let id: UUID
        let url: String
        let format: DownloadFormat
        var title: String?
    }

    private var pendingFileURL: URL {
        AppConfig.supportDirectory.appendingPathComponent("pending.json")
    }

    private func savePending() {
        let pending = jobs.filter { $0.state.isActive }.map {
            PendingJob(id: $0.id, url: $0.url, format: $0.format, title: $0.metadata?.title)
        }
        let directory = pendingFileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(pending) else { return }
        try? data.write(to: pendingFileURL, options: .atomic)
    }

    /// Lit les téléchargements laissés en plan au dernier arrêt et fait le
    /// ménage des fichiers partiels devenus orphelins. N'en relance aucun :
    /// c'est à l'utilisateur de décider, il vient peut-être de les annuler en
    /// fermant l'app.
    func loadResumable() {
        let data = (try? Data(contentsOf: pendingFileURL)) ?? Data()
        let decoded = (try? JSONDecoder().decode([PendingJob].self, from: data)) ?? []
        resumable = decoded
        DownloadEngine.prunePartials(keeping: Set(decoded.map(\.id)))
    }

    /// Reprend les téléchargements interrompus. Le même identifiant désigne le
    /// même dossier de fichiers partiels : yt-dlp repart de l'octet courant.
    func resumeAll() {
        let pending = resumable
        resumable = []
        for item in pending.reversed() {
            startDownload(urlString: item.url, format: item.format, id: item.id)
        }
    }

    func discardResumable() {
        let ids = Set(resumable.map(\.id))
        resumable = []
        for id in ids {
            try? FileManager.default.removeItem(at: DownloadEngine.partialDirectory(for: id))
        }
        savePending()
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
            // yt-dlp ne connaît ni l'un ni l'autre : sans ces deux lignes, son
            // arrivée effacerait l'avatar déjà résolu.
            merged.channelURL = metadata.channelURL ?? job.metadata?.channelURL
            merged.channelAvatarURL = metadata.channelAvatarURL ?? job.metadata?.channelAvatarURL
            job.metadata = merged
        }
    }

    /// Aperçu (titre/chaîne/durée/miniature) sans démarrer de téléchargement.
    /// Utilisé par la barre d'aperçu de l'UI et l'endpoint /api/metadata.
    /// Métadonnées d'une vidéo, extraites AU PLUS UNE FOIS.
    ///
    /// Chaque lancement de yt-dlp coûte cher : le binaire est un exécutable
    /// PyInstaller qui se déballe et réimporte tout Python à chaque appel.
    /// L'app en lançait trois pour un seul téléchargement — l'aperçu du poids
    /// au collage, les métadonnées du job, puis le téléchargement lui-même.
    /// Le cache et la déduplication des appels en vol ramènent cela à un seul.
    func fetchMetadata(urlString: String) async -> MediaMetadata? {
        let key = YouTubeLink.videoID(from: urlString) ?? urlString
        if let cached = metadataCache[key] { return cached }
        if let running = metadataTasks[key] { return await running.value }
        guard let engine else { return nil }

        let task = Task<MediaMetadata?, Never> { await engine.fetchMetadata(url: urlString) }
        metadataTasks[key] = task
        let found = await task.value
        metadataTasks[key] = nil
        if let found { metadataCache[key] = found }
        return found
    }

    /// Liste les vidéos d'une playlist, sans en extraire aucune.
    func fetchPlaylist(urlString: String) async -> Playlist? {
        guard let engine else { return nil }
        return await engine.fetchPlaylist(url: urlString)
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
        // Annulation explicite : les fragments ne resserviront pas.
        try? FileManager.default.removeItem(at: DownloadEngine.partialDirectory(for: jobID))
        savePending()
        pump()
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
        savePending()
        pump()
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
                        // Une ligne de progression peut arriver APRÈS la mise en
                        // pause : yt-dlp en avait écrit une avant de recevoir le
                        // signal. La prendre ferait avancer la barre d'un
                        // téléchargement à l'arrêt. On la jette.
                        guard job.state != .cancelled, job.state != .paused else { return }
                        job.state = .downloading
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
                    self.savePending()
                case .failed(let message):
                    self.update(jobID) {
                        if $0.state != .cancelled {
                            $0.state = .failed
                            $0.errorMessage = message
                        }
                    }
                    self.savePending()
                }
            }
            self.running[jobID] = nil
            // Une place se libère : le suivant de la file peut partir.
            self.pump()
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
