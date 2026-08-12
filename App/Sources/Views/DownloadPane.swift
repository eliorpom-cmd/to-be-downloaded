// TBD — To Be Downloaded. Copyright (C) 2026 Elior Pommier.
// Licensed under the GNU AGPL v3 or later. See LICENSE and NOTICE.
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
    /// Full metadata of the entered link: duration and per-format sizes.
    /// Costs a `yt-dlp` extraction, so it lands seconds after the link.
    @State private var preview: MediaMetadata?
    /// Title and channel of the entered link, from oEmbed — a few hundred
    /// milliseconds. What the confirmation card shows while `preview` is
    /// still being extracted.
    @State private var quickPreview: MediaMetadata?
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

            if showsLinkPreview {
                Spacer().frame(height: Theme.Space.s12)
                linkPreviewCard.frame(maxWidth: 440)
            }

            Spacer().frame(height: Theme.Space.s16)

            formatControls

            if showsMaxWarning {
                Spacer().frame(height: Theme.Space.s12)
                maxQualityWarning.frame(maxWidth: 440)
            }

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
        .animation(.easeOut(duration: 0.22), value: showsLinkPreview)
    }

    // MARK: - Max Quality

    /// Choosing Max has a consequence nobody expects, and someone hit it: at
    /// 4K the file plays in nothing Apple ships.
    ///
    /// YouTube serves H.264 up to 1080p and nothing above it — 1440p and 2160p
    /// exist only as VP9 and AV1, and AVFoundation decodes neither, so the TV
    /// app, QuickTime and Preview all open a file with no picture. The file is
    /// not broken; VLC and IINA play it fine.
    ///
    /// Warned at the moment of choosing rather than fixed behind the user's
    /// back: someone who asks for 4K should get 4K. Shown once and dismissed
    /// for good, since the default is 1080p and only a deliberate choice
    /// reaches here.
    private var showsMaxWarning: Bool {
        kind == .video && videoQuality == .max && !settings.maxQualityWarningDismissed
    }

    private var maxQualityWarning: some View {
        InlineNotice(
            symbol: "exclamationmark.triangle.fill",
            message: "Max downloads up to 4K, which YouTube only serves as VP9. "
                + "QuickTime cannot play it. You'll need another player such as "
                + "VLC or IINA.",
            actionTitle: "Got It",
            action: { settings.maxQualityWarningDismissed = true })
    }

    // MARK: - Link Preview

    /// What the pasted link actually points at, shown BEFORE the download
    /// rather than after it.
    ///
    /// It costs almost nothing: the thumbnail address is derived from the
    /// video id in the URL, with no request at all, and the title comes from
    /// one oEmbed call of a few hundred milliseconds. Cheap enough to spend
    /// while a wrong link — a stale clipboard, the video above the one you
    /// meant — can still be fixed instead of downloaded.
    ///
    /// A playlist link is excluded: the playlist sheet is already a
    /// confirmation step, and a better one.
    private var showsLinkPreview: Bool {
        isValidURL && YouTubeLink.playlistURL(from: trimmedURL) == nil
    }

    private var linkPreviewCard: some View {
        HStack(spacing: Theme.Space.s12) {
            Thumbnail(urlString: YouTubeLink.thumbnailURL(for: trimmedURL)
                        ?? quickPreview?.thumbnailURL,
                      width: 72, height: 40)

            VStack(alignment: .leading, spacing: 3) {
                if let previewTitle {
                    Text(previewTitle)
                        .font(Theme.Text.body)
                        .foregroundStyle(Theme.label)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                } else {
                    // A neutral bar, not the raw URL: the URL is already in the
                    // field right above, and it would be overwritten by the
                    // title a moment later — a line that rewrites itself reads
                    // as a glitch.
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Theme.fillSecondary)
                        .frame(width: 190, height: 9)
                        .padding(.vertical, 3)
                }

                Text(previewSubtitle)
                    .font(Theme.Text.caption)
                    .foregroundStyle(Theme.labelSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(Theme.Space.s8)
        .padding(.trailing, Theme.Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.fillTertiary,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .animation(.easeOut(duration: 0.2), value: previewTitle)
        .transition(.appearingCapsule)
    }

    /// oEmbed first: it answers long before the extraction, and both give the
    /// same title.
    private var previewTitle: String? {
        let title = quickPreview?.title ?? preview?.title
        return title?.isEmpty == false ? title : nil
    }

    private var previewSubtitle: String {
        var parts: [String] = []
        if let channel = quickPreview?.channel ?? preview?.channel, !channel.isEmpty {
            parts.append(channel)
        }
        let length = Format.duration(preview?.duration)
        if !length.isEmpty { parts.append(length) }
        return parts.isEmpty ? "Checking the link…" : parts.joined(separator: " · ")
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
        // Not on the first failure. One is usually a blink of the connection
        // or a video that no longer exists, and the app already retries once
        // by itself before anyone is told anything.
        guard manager.breakageFailures >= DownloadManager.breakageThreshold,
              let job = manager.jobs.first(where: { $0.state == .failed }),
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
                        // Deliberately not nudged. Measured on a real capture:
                        // the arrow's ink is centred on the circle, and the
                        // circle on the capsule, to within half a device pixel.
                        // What looked misaligned was the 3 pt focus ring that
                        // used to be drawn around the field — it thickened one
                        // side of the capsule and threw the eye off. Removing
                        // the ring was the fix.
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
            // Border on invalid input only. No focus halo: the caret blinking
            // in the field already says where the keyboard goes, and the ring
            // was the heaviest shape on an otherwise quiet screen.
            if hasInvalidInput {
                Capsule().strokeBorder(Theme.strokeEmphasis, lineWidth: 1)
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

            // Reserved width. The control inside changes size with the format
            // — a "1080p" popup against the words "Original quality" — and the
            // row is centred, so every switch used to slide the Video/Audio
            // toggle sideways. Widest case sets the slot.
            qualityMenu
                .frame(width: 108, alignment: .leading)

            // The estimate arrives a moment after the link, so its slot is
            // reserved too, empty or not.
            estimate
                .frame(width: Self.estimateSlot, alignment: .leading)
        }
        // Mirror of the estimate's slot. The row is centred as a whole, so
        // hanging a reserved slot off one end alone would push the toggle and
        // the quality control permanently off-centre. An equal, invisible slot
        // on the other end keeps the pair where the mockup put it, and nothing
        // in the row ever moves again.
        .padding(.leading, Self.estimateSlot + Theme.Space.s8)
        .animation(.easeOut(duration: 0.2), value: preview)
    }

    /// Widest realistic reading is "≈ 158,4 MB"; a four-digit megabyte count
    /// is already a gigabyte, and prints shorter.
    private static let estimateSlot: CGFloat = 84

    @ViewBuilder
    private var estimate: some View {
        // "≈" is intentional: yt-dlp itself only knows the size of fragmented
        // streams approximately.
        if let bytes = preview?.estimatedBytes(for: currentFormat), bytes > 0 {
            Text("≈ \(Format.bytes(bytes))")
                .font(Theme.Text.caption)
                .monospacedDigit()
                .foregroundStyle(Theme.labelSecondary)
                .lineLimit(1)
                .transition(.opacity)
        }
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
                VStack(spacing: Theme.Space.s10) {
                    Button("Download FFmpeg") {
                        Task { await ffmpeg.installIfMissing() }
                    }
                    .buttonStyle(.push)

                    // Same offer as the first-launch screen: someone who
                    // reached this card by answering "Not Now" there should
                    // find the same way out here.
                    Button("Use an FFmpeg I already have…", action: linkExistingFFmpeg)
                        .buttonStyle(.plain)
                        .font(Theme.Text.body)
                        .foregroundStyle(Theme.labelSecondary)
                }
            }
        }
    }

    private func linkExistingFFmpeg() {
        let detected = FFmpegInstaller.detectExisting()
        guard let url = FFmpegPicker.choose(startingAt: detected?.deletingLastPathComponent())
        else { return }
        Task { await ffmpeg.useExisting(at: url) }
    }

    private var ffmpegSetupTitle: String {
        switch ffmpeg.status {
        case .downloading, .checking: return "Downloading FFmpeg"
        case .installing:             return "Checking the signature"
        case .failed:                 return "FFmpeg didn't install"
        default:                      return "One thing to set up"
        }
    }

    private var ffmpegSetupMessage: String {
        switch ffmpeg.status {
        case .downloading(let fraction):
            return "\(Int(fraction * 100))% done."
        case .installing:
            return "Making sure it really comes from its publisher."
        case .failed(let message):
            return message
        default:
            return "In order to work, \(AppConfig.shortName) needs FFmpeg."
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
        quickPreview = nil
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
        quickPreview = nil
        refreshClipboard()
    }

    /// Identify the entered link, fastest source first.
    ///
    /// Debounced: typing a link by hand would otherwise fire a request per
    /// keystroke. A paste — the common case — waits this once and no more.
    private func loadPreview() async {
        quickPreview = nil
        preview = nil
        guard showsLinkPreview else { return }
        try? await Task.sleep(nanoseconds: 250_000_000)
        guard !Task.isCancelled else { return }

        let link = trimmedURL
        if let fast = await MediaMetadata.oEmbed(for: link) {
            guard !Task.isCancelled else { return }
            quickPreview = fast

            // Fetch the channel's photo NOW, while the card is on screen and
            // nobody is waiting. It used to be looked up when the download
            // started, which is the one moment the person is watching, and it
            // costs a page scrape. `ChannelAvatars` caches and folds duplicate
            // requests into one, so the download either finds it ready or
            // joins the lookup already under way.
            //
            // Detached, and its result thrown away: this task must outlive the
            // debounce cancelling us, and the cache is the whole point.
            if let key = fast.channelKey, let channel = fast.channelURL {
                Task.detached(priority: .utility) {
                    _ = await ChannelAvatars.shared.avatarURL(
                        channelKey: key, channelURL: channel)
                }
            }
        }
        // yt-dlp then fills in what oEmbed cannot know: the duration and the
        // per-format sizes the estimate is built from. Several seconds.
        let full = await manager.fetchMetadata(urlString: link)
        guard !Task.isCancelled else { return }
        preview = full
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
