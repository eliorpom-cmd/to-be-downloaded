import SwiftUI
import AppKit

/// The download row from the mockup: a capsule whose **background fills**
/// as progress advances, with the channel thumbnail on the left,
/// title, metadata on the right, and contextual affordance.
///
/// Shared by the Download screen (session) and the Library tab (section
/// "Downloading").
struct DownloadCapsule: View {
    let job: DownloadJob
    /// Queued behind others, rather than starting up.
    var waiting: Bool = false
    let onTogglePause: () -> Void
    let onCancel: () -> Void
    let onRetry: () -> Void
    /// Click on the completed row.
    let onOpen: () -> Void
    /// Click on the checkmark: removes the row from the session list.
    var onDismiss: () -> Void = {}

    @State private var hovering = false
    @State private var sweep = false

    private var isFailed: Bool { job.state == .failed }

    /// yt-dlp is running but hasn't emitted anything yet: it's unpacking
    /// and querying YouTube. Nothing to measure, but it needs to show.
    private var isPreparing: Bool { job.state == .queued && !waiting }

    var body: some View {
        ZStack(alignment: .leading) {
            // Track background.
            Capsule().fill(hovering ? Theme.rowHover : Theme.fillTertiary)

            // Progress fill, clipped by the capsule.
            if let fraction = job.progressFraction {
                GeometryReader { geo in
                    Rectangle()
                        .fill(Theme.fillPrimary)
                        .frame(width: max(0, min(1, fraction)) * geo.size.width)
                        .animation(.easeOut(duration: 0.25), value: fraction)
                }
                .clipShape(Capsule())
            }

            // Indeterminate sweep during preparation: the only honest way to
            // say "it's working" when there's nothing to measure.
            if isPreparing {
                GeometryReader { geo in
                    LinearGradient(
                        colors: [.clear, Theme.fillPrimary, .clear],
                        startPoint: .leading, endPoint: .trailing)
                        .frame(width: geo.size.width * 0.45)
                        .offset(x: sweep ? geo.size.width : -geo.size.width * 0.45)
                }
                .clipShape(Capsule())
                .allowsHitTesting(false)
                .onAppear {
                    withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                        sweep = true
                    }
                }
            }

            HStack(spacing: Theme.Space.s10) {
                ChannelAvatar(urlString: job.metadata?.channelAvatarURL,
                              channelName: job.metadata?.channel)

                // While the title is unknown, a neutral line instead of
                // the raw URL: it would display then jump to the real title.
                if job.metadata?.title == nil, job.state.isActive {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Theme.fillSecondary)
                        .frame(width: 132, height: 9)
                        .transition(.opacity)
                } else {
                    // Layout priority goes to the title: that's what the eye
                    // seeks, and metadata only has a percentage to fit.
                    Text(job.displayTitle)
                        .font(Theme.Text.body)
                        .foregroundStyle(job.state == .paused ? Theme.labelSecondary : Theme.label)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(1)
                        .transition(.opacity)
                }

                Spacer(minLength: Theme.Space.s6)

                // RESERVED width and monospace digits: the text changes on
                // every refresh, and without this the whole row — title
                // included — would shift every frame.
                Text(metaText)
                    .font(Theme.Text.caption)
                    .monospacedDigit()
                    .foregroundStyle(isFailed ? Theme.label : Theme.labelSecondary)
                    .lineLimit(1)
                    .frame(minWidth: metaWidth, alignment: .trailing)

                trailing
            }
            .padding(.leading, Theme.Space.s8)
            .padding(.trailing, Theme.Space.s12)
        }
        .frame(height: 44)
        .overlay {
            // A failure shows via border, not color.
            if isFailed {
                Capsule().strokeBorder(Theme.strokeEmphasis, lineWidth: 1)
            }
        }
        .animation(.easeOut(duration: 0.25), value: job.metadata?.title)
        .overlay(alignment: .topTrailing) { liveTooltip }
        // Otherwise the tooltip would pass UNDER the next capsule.
        .zIndex(hovering ? 1 : 0)
        .contentShape(Capsule())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        // The entire capsule is clickable once the file is there.
        // A completed row goes to the library, not Finder: stay
        // in the app, where the video has a card, thumbnail, and menu.
        .onTapGesture {
            if job.state == .completed { onOpen() }
        }
        // A completed file can be dragged to Finder or any other app.
        .onDrag {
            guard job.state == .completed, let url = job.fileURL,
                  let provider = NSItemProvider(contentsOf: url)
            else { return NSItemProvider() }
            return provider
        }
        .contextMenu { menu }
        .help(helpText)
    }

    // MARK: - Live Tooltip

    /// Bitrate and remaining time no longer fit in the row: they
    /// consumed the title space. They show on hover.
    ///
    /// SwiftUI view, NOT `.help()`: the latter places an AppKit tooltip,
    /// whose text only updates on the NEXT hover. It would stay frozen
    /// on the numbers from when you arrived, which is worse than
    /// showing nothing for a value that changes every second.
    @ViewBuilder
    private var liveTooltip: some View {
        if hovering, let text = liveDetail {
            Text(text)
                .font(Theme.Text.caption)
                .monospacedDigit()
                .foregroundStyle(Theme.label)
                .fixedSize()
                .padding(.horizontal, Theme.Space.s8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .fill(Theme.card)
                        .shadow(color: .black.opacity(0.22), radius: 8, y: 2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .strokeBorder(Theme.separator, lineWidth: 1)
                )
                .offset(y: -30)
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }

    /// Tooltip content: `nil` when there's nothing moving to report.
    private var liveDetail: String? {
        switch job.state {
        case .downloading:
            var parts: [String] = []
            let speed = Format.speed(job.progress?.speed)
            let eta = Format.eta(job.progress?.eta)
            if !speed.isEmpty { parts.append(speed) }
            if !eta.isEmpty { parts.append(eta) }
            if let done = job.progress?.downloadedBytes, let total = job.progress?.totalBytes {
                parts.append("\(Format.bytes(done)) / \(Format.bytes(total))")
            }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        case .paused:
            return "Paused at \(Int(job.overallProgress * 100))%"
        case .queued:
            return waiting ? "Waiting for a free slot" : "Starting the download engine…"
        case .merging:
            return "Merging the video and audio tracks"
        default:
            return nil
        }
    }

    private var helpText: String {
        switch job.state {
        case .failed:
            return job.errorMessage ?? "Failed"
        case .completed:
            return "Show in Library — \(job.displayTitle)"
        default:
            // Active states have the live tooltip above; the AppKit one
            // now only displays the full title.
            return job.displayTitle
        }
    }

    // MARK: - Metadata

    /// Reserved space for metadata while it changes. Narrow: it now only
    /// holds a percentage, the rest moved to the tooltip.
    private var metaWidth: CGFloat? {
        switch job.state {
        case .downloading:      return 34
        case .paused:           return 46
        case .queued, .merging: return 70
        case .completed, .failed, .cancelled: return nil
        }
    }

    private var metaText: String {
        switch job.state {
        case .queued:
            return waiting ? "Waiting…" : "Preparing…"
        case .downloading:
            // The percentage follows the overall bar, not the current stream:
            // both must tell the same story.
            return "\(Int(job.overallProgress * 100))%"
        case .paused:
            // The word, not the number: without it, a stopped bar looks like
            // a stalled download. The percentage is in the tooltip.
            return "Paused"
        case .merging:
            return "Finishing up…"
        case .completed:
            return job.fileSize.map(Format.bytes) ?? "Done"
        case .failed:
            return "Failed · Retry"
        case .cancelled:
            return "Cancelled"
        }
    }

    // MARK: - End-of-Row Affordance

    @ViewBuilder
    private var trailing: some View {
        switch job.state {
        case .queued, .downloading, .paused:
            // One affordance, always the same: cancel. Pause lives in the
            // context menu — a button that changes meaning on hover causes
            // hesitation, and no one pauses a download as often as they abandon it.
            IconButton(symbol: "xmark.circle.fill", size: 15, help: "Cancel", action: onCancel)
        case .merging:
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.7)
                .frame(width: 22, height: 22)
        case .completed:
            IconButton(symbol: "checkmark.circle.fill", size: 15,
                       help: "Remove from this list — the file stays on disk",
                       action: onDismiss)
        case .failed, .cancelled:
            IconButton(symbol: "arrow.clockwise", size: 13, help: "Try again", action: onRetry)
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private var menu: some View {
        if job.state == .completed, let url = job.fileURL {
            Button("Quick Look") { QuickLook.shared.toggle(url) }
            Button("Play") { FileOpener.play(url) }
            Button("Reveal in Finder") { FileOpener.reveal(url) }
            Divider()
        }
        if job.state == .downloading || job.state == .queued {
            Button("Pause", action: onTogglePause)
        }
        if job.state == .paused {
            Button("Resume", action: onTogglePause)
        }
        Button("Copy Link") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(job.url, forType: .string)
        }
        Button("Copy Title") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(job.displayTitle, forType: .string)
        }
        if job.state == .failed || job.state == .cancelled {
            Button("Download Again", action: onRetry)
        }
        if job.state.isActive {
            Divider()
            Button("Cancel", action: onCancel)
        }
    }
}

// MARK: - Construction from Manager

extension DownloadCapsule {
    /// Shortcut: wires actions to the manager for a given job.
    /// `onOpen` defaults to reveal in Finder; the Download screen
    /// replaces it with a navigation to the library.
    init(job: DownloadJob, manager: DownloadManager, onOpen: (() -> Void)? = nil) {
        self.init(
            job: job,
            waiting: manager.isWaiting(job),
            onTogglePause: { manager.togglePause(job.id) },
            onCancel: { manager.cancel(job.id) },
            onRetry: { manager.retry(job.id) },
            onOpen: onOpen ?? {
                if let url = job.fileURL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            },
            onDismiss: { manager.remove(job.id) }
        )
    }
}
