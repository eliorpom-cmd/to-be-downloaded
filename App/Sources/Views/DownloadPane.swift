import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Welcome screen: mascot, URL field in a capsule, format/quality choice,
/// and session downloads in capsules.
struct DownloadPane: View {
    @ObservedObject var manager: DownloadManager
    @ObservedObject var settings: AppSettings
    @ObservedObject var updater: EngineUpdater
    @ObservedObject var ffmpeg: FFmpegInstaller
    @ObservedObject var library: LibraryStore
    let goToLibrary: () -> Void

    init(manager: DownloadManager, settings: AppSettings, updater: EngineUpdater,
         ffmpeg: FFmpegInstaller, library: LibraryStore,
         goToLibrary: @escaping () -> Void) {
        _manager = ObservedObject(wrappedValue: manager)
        _settings = ObservedObject(wrappedValue: settings)
        _updater = ObservedObject(wrappedValue: updater)
        _ffmpeg = ObservedObject(wrappedValue: ffmpeg)
        _library = ObservedObject(wrappedValue: library)
        self.goToLibrary = goToLibrary
        _kind = State(initialValue: settings.defaultKind)
        _videoQuality = State(initialValue: settings.defaultVideoQuality)
        _audioBitrate = State(initialValue: settings.defaultAudioBitrate)
    }

    @State private var urlText = ""
    @State private var kind: MediaKind
    @State private var videoQuality: VideoQuality
    @State private var audioBitrate: AudioBitrate
    @FocusState private var urlFocused: Bool

    @State private var clipboardSuggestion: String?
    @State private var pasteHovering = false
    @State private var isDropTargeted = false
    /// Metadata of the entered link, for weight estimation. Nothing else is
    /// displayed: the title/thumbnail preview was not re-requested.
    @State private var preview: MediaMetadata?
    @State private var playlist: Playlist?
    @State private var loadingPlaylist = false
    /// Links already pasted or launched in this session: we no longer suggest
    /// them, as the clipboard keeps the link long after.
    @State private var handledLinks: Set<String> = []

    /// Number of capsules shown before the fade (see mockup).
    private let visibleCapsules = 2

    private var trimmedURL: String { urlText.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var isValidURL: Bool { YouTubeLink.isValid(trimmedURL) }
    private var hasInvalidInput: Bool { !trimmedURL.isEmpty && !isValidURL }

    private var currentFormat: DownloadFormat {
        DownloadFormat(kind: kind,
                       videoQuality: videoQuality,
                       audioBitrate: audioBitrate,
                       audioFormat: settings.audioFormat,
                       subtitles: settings.embedSubtitles)
    }

    /// Library entry matching the entered link, if there is one.
    private var alreadyDownloaded: LibraryItem? {
        guard isValidURL else { return nil }
        return library.existing(forURL: trimmedURL, kind: kind)
    }

    /// Session jobs, newest to oldest.
    private var sessionJobs: [DownloadJob] { manager.jobs }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: WindowChrome.trafficLightInset)
            Spacer()

            if let error = manager.setupError {
                engineError(error)
            } else if manager.needsFFmpeg {
                // Not an error: the app is completing itself. The URL field makes
                // no sense until a download can actually succeed.
                ffmpegSetup
            } else {
                content
            }

            Spacer()
            Spacer(minLength: Theme.Space.s24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, Theme.Space.s40)
        .overlay(dropHighlight)
        .onDrop(of: [.url, .text], isTargeted: $isDropTargeted, perform: handleDrop)
        .task { refreshClipboard() }
        // A link typed or pasted via keyboard also counts as "handled".
        .onChange(of: trimmedURL) { value in
            if YouTubeLink.isValid(value) { handledLinks.insert(value) }
        }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)) { _ in refreshClipboard() }
        .onReceive(NotificationCenter.default.publisher(for: .focusURLField)) { _ in
            urlFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .pasteAndDownload)) { _ in
            pasteAndDownload()
        }
        .task(id: trimmedURL) { await loadPreview() }
        .sheet(item: $playlist) { list in
            PlaylistSheet(
                playlist: list,
                focusedVideoID: YouTubeLink.videoID(from: trimmedURL),
                onDownload: downloadFromPlaylist,
                onCancel: { playlist = nil })
        }
    }

    // MARK: - Content

    private var content: some View {
        VStack(spacing: 0) {
            MascotView(size: 96, isActive: manager.jobs.contains { $0.state == .downloading })

            Spacer().frame(height: Theme.Space.s40 + Theme.Space.s16)

            urlField
                .frame(maxWidth: 500)

            if hasInvalidInput {
                Spacer().frame(height: Theme.Space.s12)
                InlineNotice(symbol: "exclamationmark.triangle.fill",
                             message: "Only YouTube links are supported.")
            } else if let existing = alreadyDownloaded {
                Spacer().frame(height: Theme.Space.s12)
                InlineNotice(
                    symbol: "checkmark.circle",
                    message: "You already have this one.",
                    actionTitle: "Reveal",
                    action: { NSWorkspace.shared.activateFileViewerSelecting([existing.fileURL]) })
                    .frame(maxWidth: 440)
            } else if !manager.resumable.isEmpty, trimmedURL.isEmpty {
                Spacer().frame(height: Theme.Space.s12)
                resumeNotice.frame(maxWidth: 440)
            } else if let kind = engineNoticeKind {
                Spacer().frame(height: Theme.Space.s12)
                engineNotice(kind).frame(maxWidth: 440)
            }

            Spacer().frame(height: Theme.Space.s16)

            formatControls

            Spacer().frame(height: Theme.Space.s24)

            // Wider than the original 320 pt: bitrate and remaining time
            // moved to a tooltip, so the title can reclaim the space
            // instead of leaving it empty.
            sessionList
                .frame(maxWidth: 440)
        }
        // The animation lives HERE, on the container, not just on the list:
        // adding a capsule pushes everything above it (mascot, field,
        // controls). Animating just the list would let that movement happen
        // all at once while the capsule itself animated — creating a stutter.
        .animation(.easeOut(duration: 0.22), value: sessionJobs.count)
    }

    // MARK: - Engine banner (yt-dlp outdated by YouTube)

    private enum EngineNoticeKind: Equatable {
        case updating
        case stale
        case alreadyCurrent
        case updated(String)
        case updateFailed(String)
    }

    /// Does the last failure look like YouTube pushing back rather than a
    /// link problem? This is the only situation where suggesting an engine
    /// update makes sense.
    private var lastBreakage: DownloadJob? {
        guard let job = manager.jobs.first(where: { $0.state == .failed }),
              let message = job.errorMessage,
              EngineUpdater.suggestsUpdate(message)
        else { return nil }
        return job
    }

    private var engineNoticeKind: EngineNoticeKind? {
        guard lastBreakage != nil else { return nil }
        switch updater.status {
        case .checking, .downloading:  return .updating
        case .upToDate:                return .alreadyCurrent
        case .installed(let version):  return .updated(version)
        case .failed(let message):     return .updateFailed(message)
        case .idle:                    return .stale
        }
    }

    @ViewBuilder
    private func engineNotice(_ kind: EngineNoticeKind) -> some View {
        switch kind {
        case .updating:
            InlineNotice(symbol: "arrow.triangle.2.circlepath",
                         message: "Updating the download engine…")

        case .stale:
            InlineNotice(
                symbol: "exclamationmark.triangle.fill",
                message: "That failure is the kind YouTube causes when it changes. "
                    + "Updating the engine usually fixes it.",
                actionTitle: "Update",
                action: updateEngine)

        case .alreadyCurrent:
            InlineNotice(
                symbol: "checkmark.circle",
                message: settings.updateChannel == .stable
                    ? "The engine is already on the latest stable build. "
                        + "Switching to the Nightly channel in Settings often helps."
                    : "The engine is already on the latest nightly build.")

        case .updated(let version):
            InlineNotice(symbol: "checkmark.circle",
                         message: "Engine updated to \(version).",
                         actionTitle: "Retry",
                         action: retryLastBreakage)

        case .updateFailed(let message):
            InlineNotice(symbol: "exclamationmark.triangle.fill",
                         message: "Engine update failed. \(message)",
                         actionTitle: "Try Again",
                         action: updateEngine)
        }
    }

    private func updateEngine() {
        Task { await updater.checkForUpdate(userInitiated: true) }
    }

    private func retryLastBreakage() {
        guard let job = lastBreakage else { return }
        manager.retry(job.id)
    }

    // MARK: - URL Field

    private var urlField: some View {
        HStack(spacing: Theme.Space.s8) {
            TextField("Paste a YouTube link…", text: $urlText)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .foregroundStyle(Theme.label)
                .focused($urlFocused)
                .onSubmit(start)

            // The clipboard holds a link: signal it IN the field, with the
            // one icon everyone recognizes. A banner below the bar said the
            // same thing but took three times the space.
            if let suggestion = clipboardSuggestion, trimmedURL.isEmpty {
                Button {
                    urlText = suggestion
                    handledLinks.insert(suggestion)
                    clipboardSuggestion = nil
                    urlFocused = true
                } label: {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 14))
                        .foregroundStyle(pasteHovering ? Theme.label : Theme.labelSecondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { pasteHovering = $0 }
                .help("Paste \(displayLink(suggestion))")
                .transition(.opacity.combined(with: .scale(scale: 0.7)))
            }

            Button(action: start) {
                ZStack {
                    Circle()
                        .fill(isValidURL ? Theme.ink : Theme.fillPrimary)
                        .frame(width: 40, height: 40)
                    // The arrow stays visible at all times: it only yields
                    // to playlist loading, which actually takes several
                    // seconds.
                    if loadingPlaylist {
                        ProgressView().controlSize(.small).scaleEffect(0.8)
                    } else {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(isValidURL ? Theme.inkOn : Theme.labelSecondary)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(!isValidURL || !manager.isReady || loadingPlaylist)
            .help(YouTubeLink.playlistURL(from: trimmedURL) != nil
                  ? "Choose what to download" : "Download")
        }
        .padding(.leading, 18)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
        .animation(.easeOut(duration: 0.18), value: clipboardSuggestion)
        .background(Theme.fillTertiary, in: Capsule())
        .overlay {
            // Neutral focus halo (not system blue) + error border.
            if hasInvalidInput {
                Capsule().strokeBorder(Theme.strokeEmphasis, lineWidth: 1)
            } else if urlFocused {
                Capsule().strokeBorder(Theme.focusRing, lineWidth: 3)
            }
        }
    }

    /// `https://` removed: the tooltip is short, every character counts.
    private func displayLink(_ raw: String) -> String {
        raw.replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
    }

    // MARK: - Format and Quality

    private var formatControls: some View {
        HStack(spacing: Theme.Space.s8) {
            // Video / Audio toggle.
            HStack(spacing: 2) {
                formatButton(.video, symbol: "film", label: "Video")
                formatButton(.audio, symbol: "music.note", label: "Audio")
            }
            .padding(2)
            .background(Theme.fillTertiary, in: RoundedRectangle(cornerRadius: Theme.Radius.control + 2, style: .continuous))

            qualityMenu

            // Expected size, once formats are known. "≈" is intentional:
            // yt-dlp itself only knows the size of fragmented streams
            // approximately.
            if let bytes = preview?.estimatedBytes(for: currentFormat), bytes > 0 {
                Text("≈ \(Format.bytes(bytes))")
                    .font(Theme.Text.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.labelSecondary)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: preview)
    }

    // MARK: - Resume After Close

    private var resumeNotice: some View {
        let count = manager.resumable.count
        return InlineNotice(
            symbol: "arrow.clockwise",
            message: count == 1
                ? "One download was interrupted when the app closed."
                : "\(count) downloads were interrupted when the app closed.",
            actionTitle: "Resume",
            action: { manager.resumeAll() },
            secondaryTitle: "Discard",
            secondaryAction: { manager.discardResumable() })
    }

    private func formatButton(_ value: MediaKind, symbol: String, label: String) -> some View {
        let selected = kind == value
        return Button { kind = value } label: {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 11))
                Text(label).font(Theme.Text.body)
            }
            .foregroundStyle(selected ? Theme.label : Theme.labelSecondary)
            .padding(.horizontal, Theme.Space.s12)
            .frame(height: 22)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .fill(selected ? Theme.card : .clear)
                    .shadow(color: selected ? .black.opacity(0.12) : .clear, radius: 1, y: 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Real macOS popup button (`Picker.menu`): it's the control the mockup
    /// imitates, and the only one that renders system chrome correctly —
    /// `.menuStyle(.borderlessButton)` ignores label decorations.
    @ViewBuilder
    private var qualityMenu: some View {
        switch kind {
        case .video:
            Picker("", selection: $videoQuality) {
                ForEach(VideoQuality.allCases) { Text($0.label).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
        case .audio:
            // Bitrate only adjusts if we re-encode. In M4A we keep the
            // original track: offering a choice would be misleading.
            if settings.audioFormat.usesBitrate {
                Picker("", selection: $audioBitrate) {
                    ForEach(AudioBitrate.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            } else {
                Text("Original quality")
                    .font(Theme.Text.body)
                    .foregroundStyle(Theme.labelSecondary)
            }
        }
    }

    // MARK: - Session List

    @ViewBuilder
    private var sessionList: some View {
        // Nothing when the list is empty: the absence is self-explanatory,
        // a message would only waste screen space.
        if !sessionJobs.isEmpty {
            VStack(spacing: Theme.Space.s8) {
                ForEach(Array(sessionJobs.prefix(visibleCapsules))) { job in
                    DownloadCapsule(job: job, manager: manager, onOpen: goToLibrary)
                        .transition(.appearingCapsule)
                }

                // Beyond two, the next one fades to a gradient and a button
                // links to the full list (mockup behavior).
                if sessionJobs.count > visibleCapsules {
                    let next = sessionJobs[visibleCapsules]
                    // Soft fade: the capsule fades gradually instead of
                    // being cut off sharply.
                    DownloadCapsule(job: next, manager: manager)
                        .mask(
                            LinearGradient(
                                stops: [
                                    .init(color: .black.opacity(0.55), location: 0),
                                    .init(color: .black.opacity(0.28), location: 0.45),
                                    .init(color: .black.opacity(0.08), location: 0.75),
                                    .init(color: .clear, location: 1),
                                ],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        .allowsHitTesting(false)
                        .frame(height: 38)
                        .clipped()

                    Button(action: goToLibrary) {
                        HStack(spacing: 4) {
                            Text("See all \(sessionJobs.count) downloads")
                            Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                        }
                        .font(Theme.Text.body)
                        .foregroundStyle(Theme.labelSecondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, Theme.Space.s2)
                }
            }
        }
    }

    // MARK: - FFmpeg Installation (First Launch)

    /// FFmpeg is not bundled with the app: the static build we shipped
    /// was compiled `--enable-nonfree`, so it is legally non-redistributable.
    /// It downloads once, from whoever has the right to distribute it.
    /// This screen replaces the welcome screen while that happens — better
    /// to own a setup step than a URL field that fails silently.
    private var ffmpegSetup: some View {
        VStack(spacing: 0) {
            MascotView(size: 96, isActive: ffmpeg.status.isBusy)

            Spacer().frame(height: Theme.Space.s40)

            Text(ffmpegSetupTitle)
                .font(Theme.Text.title3)
                .foregroundStyle(Theme.label)

            Spacer().frame(height: Theme.Space.s8)

            Text(ffmpegSetupMessage)
                .font(Theme.Text.body)
                .foregroundStyle(Theme.labelSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 400)

            Spacer().frame(height: Theme.Space.s20)

            switch ffmpeg.status {
            case .downloading(let fraction):
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .tint(Theme.label)
                    .frame(width: 260)
            case .checking, .installing:
                ProgressView().controlSize(.small)
            case .failed:
                HStack(spacing: Theme.Space.s8) {
                    Button("Try Again") {
                        Task { await ffmpeg.installIfMissing() }
                    }
                    .buttonStyle(.push)
                    Button("Where it comes from") {
                        NSWorkspace.shared.open(AppConfig.FFmpegSource.homepage)
                    }
                    .buttonStyle(.plain)
                    .font(Theme.Text.body)
                    .foregroundStyle(Theme.labelSecondary)
                }
            default:
                Button("Download FFmpeg") {
                    Task { await ffmpeg.installIfMissing() }
                }
                .buttonStyle(.push)
            }
        }
    }

    private var ffmpegSetupTitle: String {
        switch ffmpeg.status {
        case .downloading, .checking: return "Getting FFmpeg"
        case .installing:             return "Checking the signature"
        case .failed:                 return "FFmpeg didn't install"
        default:                      return "One thing to set up"
        }
    }

    private var ffmpegSetupMessage: String {
        switch ffmpeg.status {
        case .downloading(let fraction):
            return "About 56 MB, once. \(Int(fraction * 100))% done."
        case .installing:
            return "Making sure it really comes from its publisher."
        case .failed(let message):
            return message
        default:
            return "\(AppConfig.displayName) uses FFmpeg to join video and audio. "
                + "It isn't bundled — its license doesn't allow passing that build on — "
                + "so it's downloaded once from its publisher."
        }
    }

    // MARK: - Engine Error

    private func engineError(_ message: String) -> some View {
        VStack(spacing: Theme.Space.s12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 30))
                .foregroundStyle(Theme.labelSecondary)
            Text("Engine unavailable")
                .font(Theme.Text.title3)
                .foregroundStyle(Theme.label)
            Text(message)
                .font(Theme.Text.body)
                .foregroundStyle(Theme.labelSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var dropHighlight: some View {
        if isDropTargeted {
            RoundedRectangle(cornerRadius: Theme.Radius.window, style: .continuous)
                .strokeBorder(Theme.strokeEmphasis, lineWidth: 2)
                .padding(6)
                .allowsHitTesting(false)
        }
    }

    // MARK: - Actions

    private func start() {
        guard isValidURL, manager.isReady, !loadingPlaylist else { return }
        // A playlist link doesn't download by itself: ask first.
        if YouTubeLink.playlistURL(from: trimmedURL) != nil {
            loadPlaylist()
            return
        }
        launch(trimmedURL)
    }

    private func launch(_ link: String) {
        handledLinks.insert(link)
        manager.startDownload(urlString: link, format: currentFormat)
        urlText = ""
        preview = nil
        refreshClipboard()
    }

    private func loadPlaylist() {
        guard let listURL = YouTubeLink.playlistURL(from: trimmedURL) else { return }
        loadingPlaylist = true
        Task {
            let found = await manager.fetchPlaylist(urlString: listURL)
            loadingPlaylist = false
            // Unreadable playlist (private, mix, network): rather than fail,
            // do what the user clearly wanted — the video.
            guard let found else { launch(trimmedURL); return }
            playlist = found
        }
    }

    private func downloadFromPlaylist(_ entries: [Playlist.Entry]) {
        playlist = nil
        handledLinks.insert(trimmedURL)
        manager.startPlaylist(entries, format: currentFormat)
        urlText = ""
        preview = nil
        refreshClipboard()
    }

    /// Load metadata of the entered link, for weight estimation only.
    /// Debounced: we don't launch yt-dlp on every keystroke.
    private func loadPreview() async {
        preview = nil
        guard isValidURL, YouTubeLink.playlistURL(from: trimmedURL) == nil else { return }
        try? await Task.sleep(nanoseconds: 400_000_000)
        guard !Task.isCancelled else { return }
        let found = await manager.fetchMetadata(urlString: trimmedURL)
        guard !Task.isCancelled else { return }
        preview = found
    }

    private func pasteAndDownload() {
        guard let copied = NSPasteboard.general.string(forType: .string),
              YouTubeLink.isValid(copied), manager.isReady else { return }
        let link = copied.trimmingCharacters(in: .whitespacesAndNewlines)
        handledLinks.insert(link)
        manager.startDownload(urlString: link, format: currentFormat)
        refreshClipboard()
    }

    private func refreshClipboard() {
        guard trimmedURL.isEmpty,
              let copied = NSPasteboard.general.string(forType: .string),
              YouTubeLink.isValid(copied) else {
            clipboardSuggestion = nil
            return
        }
        let link = copied.trimmingCharacters(in: .whitespacesAndNewlines)
        // A link already pasted or launched is not suggested again: the
        // clipboard keeps it long after.
        clipboardSuggestion = handledLinks.contains(link) ? nil : link
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            if let url, YouTubeLink.isValid(url.absoluteString) {
                Task { @MainActor in urlText = url.absoluteString }
            }
        }
        if provider.canLoadObject(ofClass: String.self) {
            _ = provider.loadObject(ofClass: String.self) { string, _ in
                if let string, YouTubeLink.isValid(string) {
                    Task { @MainActor in
                        urlText = string.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
            }
        }
        return true
    }
}
