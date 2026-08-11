// TBD — To Be Downloaded. Copyright (C) 2026 Elior Pommier.
// Licensed under the GNU AGPL v3 or later. See LICENSE and NOTICE.
import Foundation
import SwiftUI
import AppKit

/// Shared orchestration (native UI and, later, HTTP server).
/// Holds the job queue and drives the engine.
@MainActor
final class DownloadManager: ObservableObject {

    @Published private(set) var jobs: [DownloadJob] = [] {
        didSet { updateDockBadge() }
    }
    /// Setup configuration error (missing binary, etc.).
    @Published private(set) var setupError: String?

    /// FFmpeg is still missing. This is not an error but a setup step:
    /// the app downloads it on first launch, and the interface shows
    /// progress instead of a failure message.
    @Published private(set) var needsFFmpeg = false

    private var engine: DownloadEngine?
    private var running: [UUID: DownloadEngine.Running] = [:]
    /// Animates the bar during assembly; stops as soon as no job is in it.
    private var mergeTicker: Task<Void, Never>?

    /// Jobs interrupted by app closure, offered for resume.
    @Published private(set) var resumable: [PendingJob] = []

    /// Already-extracted metadata, by video identifier, and in-flight extractions.
    private var metadataCache: [String: MediaMetadata] = [:]
    private var metadataTasks: [String: Task<MediaMetadata?, Never>] = [:]

    /// Persistent library fed with each successful download.
    let library: LibraryStore

    init(library: LibraryStore = LibraryStore()) {
        self.library = library
        buildEngine()

        // Stops all yt-dlp subprocesses on app closure (prevents orphans).
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.terminateAll() }
        }

        // yt-dlp just updated: the engine still points to the old path.
        // In-flight downloads are unaffected (they keep their inode),
        // only subsequent ones pick up the new version.
        NotificationCenter.default.addObserver(
            forName: .engineBinaryDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reconfigure() }
        }

        // Global shortcut: handled here not in a view, so it works even
        // when the window is closed — that's its whole point.
        NotificationCenter.default.addObserver(
            forName: .globalPasteAndDownload, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { _ = self?.downloadFromClipboard() }
        }

        // Same reasoning for links from outside (macOS service,
        // sharing extension, URL scheme): no window needed.
        //
        // Nothing here fires before setup is done. These are the paths that
        // bypass the window entirely, and until FFmpeg is in place they would
        // queue a download that cannot finish — from an app the person is
        // still being asked to set up.
        NotificationCenter.default.addObserver(
            forName: .externalDownloadRequest, object: nil, queue: .main
        ) { [weak self] note in
            guard let link = note.userInfo?["url"] as? String else { return }
            MainActor.assumeIsolated {
                guard AppSettings.shared.onboarded else { return }
                _ = self?.startDownload(
                    urlString: link, format: AppSettings.shared.currentDefaultFormat)
            }
        }
    }

    /// Launch the clipboard link with default settings.
    @discardableResult
    func downloadFromClipboard() -> UUID? {
        guard AppSettings.shared.onboarded,
              let copied = NSPasteboard.general.string(forType: .string),
              YouTubeLink.isValid(copied)
        else { return nil }
        return startDownload(
            urlString: copied.trimmingCharacters(in: .whitespacesAndNewlines),
            format: AppSettings.shared.currentDefaultFormat)
    }

    /// (Re)builds the engine from current settings (output folder).
    /// Called on startup and after a folder change in Settings.
    func reconfigure() { buildEngine() }

    private func buildEngine() {
        do {
            // Updated copy if it exists, bundle seed otherwise.
            let ytDlp = try BinaryLocator.effectiveYtDlp()
            // FFmpeg, on the other hand, has no seed: it is downloaded on
            // first launch (the build we shipped was not redistributable).
            // ffprobe lives in the same folder and is verified at the same time.
            let ffmpeg = try BinaryLocator.effectiveFFmpeg()

            // Combined CA bundle (Mozilla + macOS system keychain) generated on
            // startup: handles local TLS interceptors (Qustodio, AV, VPN…).
            let trustBundle = TrustStore.prepareBundle(
                shippedCACert: BinaryLocator.resourceInBin("cacert.pem"))

            let settings = AppSettings.shared
            engine = DownloadEngine(config: .init(
                ytDlp: ytDlp,
                ffmpegDirectory: ffmpeg.deletingLastPathComponent(),
                outputDirectory: settings.outputDirectory,
                trustBundle: trustBundle,
                outputPattern: settings.outputPattern,
                subtitleLanguages: settings.subtitleLanguages,
                autoSubtitles: settings.autoSubtitles
            ))
            setupError = nil
            needsFFmpeg = false
        } catch BinaryLocator.BinaryError.notInstalled {
            engine = nil
            setupError = nil
            needsFFmpeg = true
        } catch {
            engine = nil
            setupError = error.localizedDescription
            needsFFmpeg = false
        }
    }

    var isReady: Bool { engine != nil }

    /// Number of downloads still occupying the engine (Dock badge / menu bar).
    var activeCount: Int {
        jobs.filter { $0.state.isActive }.count
    }

    /// Session jobs still in flight, most recent first.
    var activeJobs: [DownloadJob] {
        jobs.filter { $0.state.isActive }
    }

    /// Badge + progress bar on the Dock icon. The fraction is the
    /// AVERAGE of in-flight downloads: a single bar for a single
    /// message, "here is where the batch stands."
    private func updateDockBadge() {
        let active = jobs.filter { $0.state.isActive }
        let fraction = active.isEmpty
            ? nil
            : active.reduce(0.0) { $0 + $1.overallProgress } / Double(active.count)
        DockProgress.update(fraction: fraction, badge: active.count)
    }

    /// Terminates all in-progress downloads (app closure).
    func terminateAll() {
        for run in running.values { run.cancel() }
    }

    /// Queues a download. Returns the job id (nil if refused).
    ///
    /// "Queued" not "starts": beyond `maxConcurrent`, the job waits its turn.
    /// Launching ten transfers at once won't go faster — bandwidth doesn't
    /// change — but delays the first usable file and makes all remaining
    /// times dishonest.
    @discardableResult
    func startDownload(urlString: String, format: DownloadFormat, id: UUID = UUID()) -> UUID? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, engine != nil else { return nil }

        let job = DownloadJob(url: trimmed, format: format, id: id)
        jobs.insert(job, at: 0)

        // Title and channel in two stages: oEmbed responds in a few hundred
        // milliseconds, yt-dlp in a few seconds. Without the first, the line
        // remained anonymous throughout the start of the download.
        // (The thumbnail is inferred from the URL — see `DownloadJob.thumbnailURL`.)
        let jobID = job.id
        Task { [weak self] in
            guard let quick = await MediaMetadata.oEmbed(for: trimmed) else { return }
            self?.apply(quick, to: jobID, overwrite: false)
            // The channel's profile photo requires separate resolution, and is
            // cached only from the second download of the same channel. It thus
            // arrives AFTER the name, which is the useful order.
            guard let key = quick.channelKey, let channelURL = quick.channelURL,
                  let avatar = await ChannelAvatars.shared.avatarURL(
                    channelKey: key, channelURL: channelURL)
            else { return }
            self?.update(jobID) { $0.metadata?.channelAvatarURL = avatar }
        }
        // Goes through the cache: if the weight preview already extracted this
        // video while the user was hesitating, nothing is restarted.
        Task { [weak self] in
            guard let meta = await self?.fetchMetadata(urlString: trimmed) else { return }
            self?.apply(meta, to: jobID, overwrite: true)
        }

        savePending()
        pump()
        return job.id
    }

    /// Queues all chosen videos from a playlist, in order.
    func startPlaylist(_ entries: [Playlist.Entry], format: DownloadFormat) {
        // In reverse: `startDownload` inserts at head, so starting from the
        // end leaves the list in playlist order on screen.
        for entry in entries.reversed() {
            startDownload(urlString: entry.url, format: format)
        }
    }

    // MARK: - Queue

    /// Number of jobs actually occupying the engine.
    private var activeSlots: Int {
        jobs.filter { running[$0.id] != nil && $0.state.isActive }.count
    }

    /// Launches as many queued jobs as the limit allows, from oldest to
    /// most recent — the order they were requested.
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
                // The state stays `queued`: yt-dlp must first start and query
                // YouTube, which takes a very visible amount of time.
                // Announcing "downloading" at that point would show 0% and a
                // dead bar for that entire time. The first progress event is what
                // will flip the state.
                observe(run, jobID: job.id)
            } catch {
                jobs[index].state = .failed
                jobs[index].errorMessage = error.localizedDescription
            }
        }
    }

    /// A job waiting behind others, rather than starting.
    func isWaiting(_ job: DownloadJob) -> Bool {
        job.state == .queued && running[job.id] == nil
    }

    // MARK: - Resume after closure

    /// What's needed to restart an interrupted job.
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

    /// Reads downloads left in limbo at last shutdown and cleans up partial
    /// files that became orphaned. Relaunches none: it's up to the user to
    /// decide — they may have just canceled them by closing the app.
    func loadResumable() {
        let data = (try? Data(contentsOf: pendingFileURL)) ?? Data()
        let decoded = (try? JSONDecoder().decode([PendingJob].self, from: data)) ?? []
        resumable = decoded
        DownloadEngine.prunePartials(keeping: Set(decoded.map(\.id)))
    }

    /// Resumes interrupted downloads. The same identifier designates the
    /// same partial-file folder: yt-dlp restarts from the current byte.
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

    /// Records metadata on a job.
    ///
    /// The thumbnail is FROZEN to the one inferred from the YouTube identifier
    /// when it exists: both sources offer different variants, and changing its
    /// URL would restart a load — the avatar would flicker once the download
    /// is already running.
    private func apply(_ metadata: MediaMetadata, to jobID: UUID, overwrite: Bool) {
        update(jobID) { job in
            guard overwrite || job.metadata == nil else { return }
            var merged = metadata
            merged.thumbnailURL = YouTubeLink.thumbnailURL(for: job.url)
                ?? job.metadata?.thumbnailURL ?? metadata.thumbnailURL
            // yt-dlp knows neither of those: without these two lines, its arrival
            // would erase the already-resolved avatar.
            merged.channelURL = metadata.channelURL ?? job.metadata?.channelURL
            merged.channelAvatarURL = metadata.channelAvatarURL ?? job.metadata?.channelAvatarURL
            job.metadata = merged
        }
    }

    /// Preview (title/channel/duration/thumbnail) without starting a download.
    /// Used by the UI preview bar and the /api/metadata endpoint.
    /// Video metadata, extracted AT MOST ONCE.
    ///
    /// Each yt-dlp launch is expensive: the binary is a PyInstaller executable
    /// that unpacks and reimports all of Python on each call.
    /// The app launched it three times for a single download — the weight
    /// preview on paste, the job metadata, then the download itself.
    /// Caching and deduplication of in-flight calls brings that down to one.
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

    /// Lists the videos from a playlist, without extracting any of them.
    func fetchPlaylist(urlString: String) async -> Playlist? {
        guard let engine else { return nil }
        return await engine.fetchPlaylist(url: urlString)
    }

    // MARK: - Access for HTTP server (Sendable data)

    /// JSON snapshot of all jobs.
    func snapshot() -> [JobDTO] { jobs.map(JobDTO.init) }

    /// URL of the finished file from a completed job, else nil.
    func fileURL(forJobID id: UUID) -> URL? {
        guard let job = jobs.first(where: { $0.id == id }), job.state == .completed else { return nil }
        return job.fileURL
    }

    func cancel(_ jobID: UUID) {
        running[jobID]?.cancel()
        update(jobID) { if $0.state.isActive { $0.state = .cancelled } }
        // Explicit cancellation: the fragments won't be reused.
        try? FileManager.default.removeItem(at: DownloadEngine.partialDirectory(for: jobID))
        savePending()
        pump()
    }

    /// Suspends the yt-dlp process. The `.part` stays in place, resume
    /// restarts from the current byte.
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

    /// Toggle pause/resume from a single capsule button.
    func togglePause(_ jobID: UUID) {
        guard let job = jobs.first(where: { $0.id == jobID }) else { return }
        job.state == .paused ? resume(jobID) : pause(jobID)
    }

    func removeCompleted() {
        jobs.removeAll { $0.state == .completed || $0.state == .failed || $0.state == .cancelled }
    }

    /// Removes a single job (cancels first if it's still running).
    func remove(_ jobID: UUID) {
        running[jobID]?.cancel()
        running[jobID] = nil
        jobs.removeAll { $0.id == jobID }
        savePending()
        pump()
    }

    /// Forget a finished download completely.
    ///
    /// A library entry and the session row that produced it are the same
    /// download seen twice — `LibraryItem` is built with the job's own id.
    /// Removing only the entry left the row standing on the Download screen
    /// and, because that list is what the LAN server serves, on every phone
    /// pointed at this Mac.
    func forget(_ itemID: UUID) {
        library.remove(itemID)
        remove(itemID)
    }

    /// Same, for "Clear Library". Only finished rows go: a download still
    /// running has no entry yet and must not be cancelled by a list command.
    func forgetAll() {
        library.removeAll()
        removeCompleted()
    }

    /// Restarts a failed/canceled download with the same URL and format.
    @discardableResult
    func retry(_ jobID: UUID) -> UUID? {
        guard let job = jobs.first(where: { $0.id == jobID }) else { return nil }
        return startDownload(urlString: job.url, format: job.format)
    }

    // MARK: - Private

    private func observe(_ run: DownloadEngine.Running, jobID: UUID) {
        Task { [weak self] in
            guard let self else { return }
            for await event in run.events {
                switch event {
                case .progress(let p):
                    self.update(jobID) { job in
                        // A progress line can arrive AFTER pause: yt-dlp wrote one before
                        // receiving the signal. Taking it would advance the bar of a
                        // download at rest. We discard it.
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
            // A slot is freed: the next job in the queue can go.
            self.pump()
        }
    }

    // MARK: - Overall progress

    /// Projects the current stream's progress onto the single bar, never
    /// receding. A filename change signals the switch to the next stream
    /// (video → audio).
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

    /// Advances the bar during ffmpeg assembly, whose progress we cannot
    /// measure: asymptotic approach to the goal — fast at first, slower and
    /// slower, never reaching 100% before the actual end.
    /// This is the convention for a wait of unknown duration.
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
