import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject private var manager: DownloadManager
    @ObservedObject private var server: ServerController
    @ObservedObject private var settings: AppSettings

    init(manager: DownloadManager, server: ServerController, settings: AppSettings) {
        _manager = ObservedObject(wrappedValue: manager)
        _server = ObservedObject(wrappedValue: server)
        _settings = ObservedObject(wrappedValue: settings)
        _kind = State(initialValue: settings.defaultKind)
        _videoQuality = State(initialValue: settings.defaultVideoQuality)
        _audioBitrate = State(initialValue: settings.defaultAudioBitrate)
    }

    @State private var urlText = ""
    @State private var kind: MediaKind
    @State private var videoQuality: VideoQuality
    @State private var audioBitrate: AudioBitrate
    @State private var showQRPopover = false
    @FocusState private var urlFocused: Bool

    // Aperçu du média (titre/miniature) pendant que l'URL est saisie.
    @State private var preview: MediaMetadata?
    @State private var previewLoading = false

    // Lien YouTube détecté dans le presse-papier (proposé en un clic).
    @State private var clipboardSuggestion: String?

    // Retour visuel du glisser-déposer d'un lien sur la fenêtre.
    @State private var isDropTargeted = false

    // Horloge lente pour ré-évaluer « appareil connecté » (ping récent).
    @State private var now = Date()

    private var currentFormat: DownloadFormat {
        DownloadFormat(kind: kind, videoQuality: videoQuality, audioBitrate: audioBitrate)
    }

    private var isDownloadingAny: Bool {
        manager.jobs.contains { $0.state == .downloading }
    }

    private static let allowedHosts: Set<String> = [
        "youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com",
        "youtu.be", "www.youtu.be",
    ]

    private var trimmedURL: String { urlText.trimmingCharacters(in: .whitespacesAndNewlines) }

    private static func isYouTubeURL(_ string: String) -> Bool {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed), let host = url.host?.lowercased()
        else { return false }
        return allowedHosts.contains(host)
    }

    private var isValidYouTubeURL: Bool { Self.isYouTubeURL(trimmedURL) }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            serverBar

            if let error = manager.setupError {
                setupErrorBanner(error)
            } else {
                inputCard
                jobList
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 40)          // dégage les feux tricolores (title bar masquée)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.canvas.ignoresSafeArea())
        .overlay(dropHighlight)
        .onDrop(of: [.url, .text], isTargeted: $isDropTargeted, perform: handleDrop)
        .task {
            server.start()
            Notifier.shared.requestAuthorization()
            refreshClipboard()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)) { _ in refreshClipboard() }
        .onReceive(NotificationCenter.default.publisher(for: .focusURLField)) { _ in
            urlFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .pasteAndDownload)) { _ in
            pasteAndDownload()
        }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { now = $0 }
        // Aperçu debouncé : relancé à chaque changement d'URL, annulé si elle change.
        .task(id: trimmedURL) { await loadPreview() }
    }

    // MARK: - Network access

    private enum RemoteStatus { case stopped, active, connected }

    private var remoteStatus: RemoteStatus {
        guard server.isRunning else { return .stopped }
        if let ping = server.lastClientPing, now.timeIntervalSince(ping) < 4 { return .connected }
        return .active
    }

    private var serverBar: some View {
        HStack(spacing: 12) {
            Image(systemName: statusSymbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(remoteStatus == .stopped ? Theme.inkSecondary : Theme.ink)
                .frame(width: 22)
                .symbolRenderingMode(.hierarchical)

            VStack(alignment: .leading, spacing: 1) {
                Text(statusTitle)
                    .font(.subheadline.weight(.medium))
                Text(statusSubtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1)
            }

            Spacer()

            if server.isRunning {
                Button {
                    showQRPopover = true
                } label: {
                    Image(systemName: "qrcode")
                }
                .buttonStyle(.secondaryCapsule)
                .help("Show QR code")
                .popover(isPresented: $showQRPopover, arrowEdge: .bottom) {
                    qrPopoverContent
                }
            }

            Button(server.isRunning ? "Stop" : "Start") {
                server.isRunning ? server.stop() : server.start()
            }
            .buttonStyle(.secondaryCapsule)
        }
        .cardStyle(padding: Theme.Spacing.md)
    }

    private var statusSymbol: String {
        switch remoteStatus {
        case .stopped:   return "wifi.slash"
        case .active:    return "antenna.radiowaves.left.and.right"
        case .connected: return "iphone.radiowaves.left.and.right"
        }
    }

    private var statusTitle: String {
        switch remoteStatus {
        case .stopped:   return "Server stopped"
        case .active:    return "Network access active"
        case .connected: return "Device connected"
        }
    }

    private var statusSubtitle: String {
        switch remoteStatus {
        case .stopped:
            return server.lastError ?? "Start to control from the network"
        case .active:
            return "Control from another device on the network"
        case .connected:
            return "A device is controlling this Mac"
        }
    }

    @ViewBuilder
    private var qrPopoverContent: some View {
        if let url = server.url, let qr = QRGenerator.image(from: url) {
            VStack(spacing: 14) {
                Image(nsImage: qr)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 160, height: 160)
                    .padding(12)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))

                VStack(spacing: 4) {
                    Text("Open on your phone")
                        .font(.headline)
                    Text("Scan with your camera, or enter this address in a browser on the same network:")
                        .font(.caption)
                        .foregroundStyle(Theme.inkSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(url)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(.top, 2)
                }
            }
            .padding(20)
            .frame(width: 260)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            MascotView(size: 40, isActive: isDownloadingAny)

            VStack(alignment: .leading, spacing: 4) {
                Text(AppConfig.displayName)
                    .font(.system(size: 30, weight: .bold))
                Text("Paste a link, pick a format, get the file.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSecondary)
            }

            Spacer()

            Button {
                settings.cycleAppearance()
            } label: {
                Image(systemName: settings.appearance.symbol)
            }
            .buttonStyle(.secondaryCapsule)
            .help("Appearance: \(settings.appearance.label)")
        }
    }

    // MARK: - Input card

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                TextField("https://…", text: $urlText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .focused($urlFocused)
                    .padding(12)
                    .background(Theme.subtleFill, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                            .strokeBorder(urlFocused ? Theme.ink.opacity(0.5) : .clear, lineWidth: 1)
                    )
                    .onSubmit(start)

                if let suggestion = clipboardSuggestion, trimmedURL.isEmpty {
                    Button {
                        urlText = suggestion
                        clipboardSuggestion = nil
                    } label: {
                        Label("Paste copied link", systemImage: "doc.on.clipboard")
                    }
                    .buttonStyle(.secondaryCapsule)
                }

                if !trimmedURL.isEmpty && !isValidYouTubeURL {
                    Text("Enter a valid YouTube link (youtube.com or youtu.be).")
                        .font(.caption)
                        .foregroundStyle(Theme.inkSecondary)
                }
            }

            if isValidYouTubeURL { previewRow }

            HStack(spacing: 12) {
                Picker("", selection: $kind) {
                    ForEach(MediaKind.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()

                qualityPicker

                Spacer()

                Button(action: start) {
                    Label("Download", systemImage: "arrow.down.circle.fill")
                }
                .buttonStyle(.primaryCapsule)
                .disabled(!isValidYouTubeURL || !manager.isReady)
                .keyboardShortcut(.defaultAction)
            }
        }
        .cardStyle()
    }

    // Aperçu du média sous le champ URL : miniature + titre + chaîne/durée.
    @ViewBuilder
    private var previewRow: some View {
        HStack(spacing: 12) {
            Thumbnail(urlString: preview?.thumbnailURL, width: 96, height: 54)

            VStack(alignment: .leading, spacing: 3) {
                if let preview {
                    Text(preview.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        if let channel = preview.channel, !channel.isEmpty {
                            Text(channel).lineLimit(1)
                        }
                        let d = Format.duration(preview.duration)
                        if !d.isEmpty {
                            if preview.channel?.isEmpty == false { Text("·") }
                            Text(d)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(Theme.inkSecondary)
                } else if previewLoading {
                    Text("Loading preview…")
                        .font(.caption)
                        .foregroundStyle(Theme.inkSecondary)
                } else {
                    Text("Ready to download")
                        .font(.caption)
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Theme.subtleFill.opacity(0.6),
                    in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
    }

    @ViewBuilder
    private var qualityPicker: some View {
        switch kind {
        case .video:
            Picker("Quality", selection: $videoQuality) {
                ForEach(VideoQuality.allCases) { Text($0.label).tag($0) }
            }
            .fixedSize()
        case .audio:
            Picker("Bitrate", selection: $audioBitrate) {
                ForEach(AudioBitrate.allCases) { Text($0.label).tag($0) }
            }
            .fixedSize()
        }
    }

    // MARK: - Job list

    private var jobList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Downloads")
                    .font(.headline)
                Spacer()
                if manager.jobs.contains(where: { $0.state != .downloading && $0.state != .queued }) {
                    Button("Clear completed", action: manager.removeCompleted)
                        .buttonStyle(.plain)
                        .font(.callout)
                        .foregroundStyle(Theme.ink)
                        .underline()
                }
            }

            if manager.jobs.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(manager.jobs) { job in
                            JobRow(
                                job: job,
                                onCancel: { manager.cancel(job.id) },
                                onRemove: { manager.remove(job.id) },
                                onRetry: { manager.retry(job.id) }
                            )
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            MascotView(size: 56)
                .padding(.bottom, 4)
            Text("No downloads yet")
                .font(.headline)
            Text("Paste or drop a YouTube link above to get started.")
                .font(.subheadline)
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
    }

    private func setupErrorBanner(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Engine unavailable", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.ink)
                .font(.headline)
            Text(message).foregroundStyle(Theme.inkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: Theme.Spacing.md)
    }

    // Liseré discret quand on survole la fenêtre avec un lien.
    @ViewBuilder
    private var dropHighlight: some View {
        if isDropTargeted {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.ink, lineWidth: 2)
                .padding(8)
                .allowsHitTesting(false)
        }
    }

    // MARK: - Actions

    private func start() {
        guard isValidYouTubeURL, manager.isReady else { return }
        manager.startDownload(urlString: trimmedURL, format: currentFormat)
        urlText = ""
        preview = nil
        refreshClipboard()
    }

    /// ⌘⇧V : colle le presse-papier et lance immédiatement si c'est un lien valide.
    private func pasteAndDownload() {
        guard let copied = NSPasteboard.general.string(forType: .string),
              Self.isYouTubeURL(copied), manager.isReady else { return }
        manager.startDownload(urlString: copied.trimmingCharacters(in: .whitespacesAndNewlines),
                              format: currentFormat)
        refreshClipboard()
    }

    /// Charge l'aperçu après un court délai (debounce), annulable via .task(id:).
    private func loadPreview() async {
        preview = nil
        guard isValidYouTubeURL else { previewLoading = false; return }
        previewLoading = true
        try? await Task.sleep(nanoseconds: 400_000_000)
        if Task.isCancelled { return }
        let meta = await manager.fetchMetadata(urlString: trimmedURL)
        if Task.isCancelled { return }
        preview = meta
        previewLoading = false
    }

    /// Met à jour la suggestion presse-papier si un lien YouTube y est copié.
    private func refreshClipboard() {
        guard trimmedURL.isEmpty,
              let copied = NSPasteboard.general.string(forType: .string),
              Self.isYouTubeURL(copied) else {
            clipboardSuggestion = nil
            return
        }
        clipboardSuggestion = copied.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            if let url, Self.isYouTubeURL(url.absoluteString) {
                Task { @MainActor in urlText = url.absoluteString }
                return
            }
        }
        // Repli : lien déposé en texte brut.
        if provider.canLoadObject(ofClass: String.self) {
            _ = provider.loadObject(ofClass: String.self) { string, _ in
                if let string, Self.isYouTubeURL(string) {
                    Task { @MainActor in urlText = string.trimmingCharacters(in: .whitespacesAndNewlines) }
                }
            }
        }
        return true
    }
}

// MARK: - Thumbnail

/// Miniature 16:9 avec coins arrondis ; repli monochrome si indisponible.
struct Thumbnail: View {
    let urlString: String?
    var width: CGFloat
    var height: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Theme.subtleFill)
            .frame(width: width, height: height)
            .overlay {
                if let urlString, let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().aspectRatio(contentMode: .fill)
                        case .failure:
                            placeholder
                        default:
                            ProgressView().controlSize(.small)
                        }
                    }
                } else {
                    placeholder
                }
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var placeholder: some View {
        Image(systemName: "film")
            .font(.system(size: height * 0.4, weight: .light))
            .foregroundStyle(Theme.inkSecondary)
    }
}

// MARK: - Job row

struct JobRow: View {
    let job: DownloadJob
    let onCancel: () -> Void
    let onRemove: () -> Void
    let onRetry: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            if let thumb = job.metadata?.thumbnailURL {
                Thumbnail(urlString: thumb, width: 72, height: 40)
            } else {
                stateIcon
                    .font(.title3)
                    .frame(width: 22)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(job.displayTitle)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 6) {
                    if let channel = job.metadata?.channel, !channel.isEmpty {
                        Text(channel)
                        Text("·")
                    }
                    Text(job.format.shortLabel)
                }
                .font(.caption)
                .foregroundStyle(Theme.inkSecondary)
                .lineLimit(1)

                content
            }

            Spacer(minLength: 0)

            actions
        }
        .cardStyle(padding: Theme.Spacing.md)
        .contextMenu {
            Button("Copy link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(job.url, forType: .string)
            }
            if job.metadata?.title != nil {
                Button("Copy title") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(job.displayTitle, forType: .string)
                }
            }
            if job.state == .completed, let url = job.fileURL {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                Button("Open") { NSWorkspace.shared.open(url) }
            }
            if job.state == .failed || job.state == .cancelled {
                Button("Try again", action: onRetry)
            }
            Divider()
            Button("Remove", role: .destructive, action: onRemove)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch job.state {
        case .queued:
            Text("Queued…").font(.caption).foregroundStyle(Theme.inkSecondary)
        case .downloading:
            VStack(alignment: .leading, spacing: 4) {
                if let fraction = job.progress?.fraction {
                    ProgressView(value: fraction)
                } else {
                    ProgressView().controlSize(.small)
                }
                HStack(spacing: 10) {
                    if let p = job.progress {
                        Text("\(Format.bytes(p.downloadedBytes)) / \(Format.bytes(p.totalBytes))")
                        let speed = Format.speed(p.speed)
                        if !speed.isEmpty { Text("· \(speed)") }
                        let eta = Format.eta(p.eta)
                        if !eta.isEmpty { Text("· \(eta)") }
                    }
                }
                .font(.caption2)
                .foregroundStyle(Theme.inkSecondary)
            }
        case .completed:
            HStack(spacing: 6) {
                Text("Done")
                if let size = job.fileSize {
                    Text("· \(Format.bytes(size))")
                }
            }
            .font(.caption)
            .foregroundStyle(Theme.inkSecondary)
        case .failed:
            Text(job.errorMessage ?? "Failed")
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.ink)
                .lineLimit(3)
        case .cancelled:
            Text("Cancelled").font(.caption).foregroundStyle(Theme.inkSecondary)
        }
    }

    @ViewBuilder
    private var stateIcon: some View {
        switch job.state {
        case .queued:      Image(systemName: "clock").foregroundStyle(Theme.inkSecondary)
        case .downloading: Image(systemName: "arrow.down.circle").foregroundStyle(Theme.ink)
        case .completed:   Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.inkSecondary)
        case .failed:      Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.ink)
        case .cancelled:   Image(systemName: "minus.circle").foregroundStyle(Theme.inkSecondary)
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch job.state {
        case .downloading, .queued:
            Button(role: .cancel, action: onCancel) {
                Image(systemName: "stop.circle")
            }
            .buttonStyle(.borderless)
            .help("Cancel")
        case .completed:
            HStack(spacing: 8) {
                if let url = job.fileURL {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    } label: { Image(systemName: "folder") }
                        .buttonStyle(.borderless)
                        .help("Show in Finder")
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: { Image(systemName: "play.circle") }
                        .buttonStyle(.borderless)
                        .help("Open")
                }
                removeButton
            }
        case .failed:
            HStack(spacing: 8) {
                Button(action: onRetry) { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                    .help("Try again")
                removeButton
            }
        case .cancelled:
            removeButton
        }
    }

    private var removeButton: some View {
        Button(action: onRemove) { Image(systemName: "xmark") }
            .buttonStyle(.borderless)
            .foregroundStyle(Theme.inkSecondary)
            .help("Remove")
    }
}

#Preview {
    ContentView(
        manager: DownloadManager(),
        server: ServerController(downloads: DownloadManager()),
        settings: AppSettings.shared
    )
}
