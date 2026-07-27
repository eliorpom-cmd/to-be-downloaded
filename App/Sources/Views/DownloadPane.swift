import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Écran d'accueil : logo, champ URL en capsule, choix format/qualité,
/// et les téléchargements de la session en capsules.
struct DownloadPane: View {
    @ObservedObject var manager: DownloadManager
    @ObservedObject var settings: AppSettings
    @ObservedObject var updater: EngineUpdater
    let goToLibrary: () -> Void

    init(manager: DownloadManager, settings: AppSettings, updater: EngineUpdater,
         goToLibrary: @escaping () -> Void) {
        _manager = ObservedObject(wrappedValue: manager)
        _settings = ObservedObject(wrappedValue: settings)
        _updater = ObservedObject(wrappedValue: updater)
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
    /// Liens déjà collés ou lancés depuis cette session : on ne les repropose
    /// plus, le presse-papier gardant le lien longtemps après.
    @State private var handledLinks: Set<String> = []

    /// Nombre de capsules affichées avant le fondu (cf. maquette).
    private let visibleCapsules = 2

    private var trimmedURL: String { urlText.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var isValidURL: Bool { YouTubeLink.isValid(trimmedURL) }
    private var hasInvalidInput: Bool { !trimmedURL.isEmpty && !isValidURL }

    private var currentFormat: DownloadFormat {
        DownloadFormat(kind: kind, videoQuality: videoQuality, audioBitrate: audioBitrate)
    }

    /// Jobs de la session, du plus récent au plus ancien.
    private var sessionJobs: [DownloadJob] { manager.jobs }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: WindowChrome.trafficLightInset)
            Spacer()

            if let error = manager.setupError {
                engineError(error)
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
        // Un lien tapé ou collé au clavier compte aussi comme « traité ».
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
    }

    // MARK: - Contenu

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
            } else if let kind = engineNoticeKind {
                Spacer().frame(height: Theme.Space.s12)
                engineNotice(kind).frame(maxWidth: 440)
            }

            Spacer().frame(height: Theme.Space.s16)

            formatControls

            Spacer().frame(height: Theme.Space.s24)

            sessionList
                .frame(maxWidth: 320)
        }
    }

    // MARK: - Bandeau moteur (yt-dlp dépassé par YouTube)

    private enum EngineNoticeKind: Equatable {
        case updating
        case stale
        case alreadyCurrent
        case updated(String)
        case updateFailed(String)
    }

    /// Le dernier échec ressemble-t-il à une parade YouTube plutôt qu'à un
    /// problème de lien ? C'est la seule situation où proposer une mise à jour
    /// du moteur est pertinent.
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

    // MARK: - Champ URL

    private var urlField: some View {
        HStack(spacing: Theme.Space.s8) {
            TextField("Paste a YouTube link…", text: $urlText)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .foregroundStyle(Theme.label)
                .focused($urlFocused)
                .onSubmit(start)

            // Le presse-papier contient un lien : on le signale DANS le champ,
            // par la seule icône que tout le monde reconnaît. Un bandeau sous
            // la barre disait la même chose en occupant trois fois la place.
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
                    // La flèche reste visible en permanence : elle ne cède plus
                    // la place à un indicateur d'activité au collage.
                    Image(systemName: "arrow.down")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(isValidURL ? Theme.inkOn : Theme.labelSecondary)
                }
            }
            .buttonStyle(.plain)
            .disabled(!isValidURL || !manager.isReady)
            .help("Download")
        }
        .padding(.leading, 18)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
        .animation(.easeOut(duration: 0.18), value: clipboardSuggestion)
        .background(Theme.fillTertiary, in: Capsule())
        .overlay {
            // Halo de focus neutre (pas le bleu système) + liseré d'erreur.
            if hasInvalidInput {
                Capsule().strokeBorder(Theme.strokeEmphasis, lineWidth: 1)
            } else if urlFocused {
                Capsule().strokeBorder(Theme.focusRing, lineWidth: 3)
            }
        }
    }

    /// `https://` retiré : l'infobulle est courte, chaque caractère compte.
    private func displayLink(_ raw: String) -> String {
        raw.replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
    }

    // MARK: - Format et qualité

    private var formatControls: some View {
        HStack(spacing: Theme.Space.s8) {
            // Bascule Video / Audio.
            HStack(spacing: 2) {
                formatButton(.video, symbol: "film", label: "Video")
                formatButton(.audio, symbol: "music.note", label: "Audio")
            }
            .padding(2)
            .background(Theme.fillTertiary, in: RoundedRectangle(cornerRadius: Theme.Radius.control + 2, style: .continuous))

            qualityMenu
        }
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

    /// Vrai popup button macOS (`Picker.menu`) : c'est le contrôle que la
    /// maquette imite, et le seul qui rende la chrome système correctement —
    /// `.menuStyle(.borderlessButton)` ignore les décorations du libellé.
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
            Picker("", selection: $audioBitrate) {
                ForEach(AudioBitrate.allCases) { Text($0.label).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
        }
    }

    // MARK: - Liste de session

    @ViewBuilder
    private var sessionList: some View {
        // Rien quand la liste est vide : l'absence se comprend d'elle-même,
        // un message ne ferait qu'occuper l'écran.
        if !sessionJobs.isEmpty {
            VStack(spacing: Theme.Space.s8) {
                ForEach(Array(sessionJobs.prefix(visibleCapsules))) { job in
                    DownloadCapsule(job: job, manager: manager)
                        .transition(.appearingCapsule)
                }

                // Au-delà de deux, la suivante s'estompe en dégradé et un bouton
                // renvoie vers la liste complète (comportement de la maquette).
                if sessionJobs.count > visibleCapsules {
                    let next = sessionJobs[visibleCapsules]
                    // Fondu doux : la capsule s'efface progressivement au lieu
                    // d'être tranchée net.
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
            // Un lancement se voit : la capsule se déplie depuis le haut au
            // lieu d'apparaître d'un coup. Ressort peu élastique — l'effet doit
            // se remarquer sans se faire attendre.
            .animation(.spring(response: 0.34, dampingFraction: 0.82),
                       value: sessionJobs.map(\.id))
        }
    }

    // MARK: - Erreur moteur

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
        guard isValidURL, manager.isReady else { return }
        handledLinks.insert(trimmedURL)
        manager.startDownload(urlString: trimmedURL, format: currentFormat)
        urlText = ""
        refreshClipboard()
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
        // Un lien déjà collé ou déjà lancé ne se repropose pas : le
        // presse-papier, lui, le garde longtemps après.
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
