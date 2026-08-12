// TBD — To Be Downloaded. Copyright (C) 2026 Elior Pommier.
// Licensed under the GNU AGPL v3 or later. See LICENSE and NOTICE.
import SwiftUI
import AppKit

/// Library: what's currently downloading (capsules, like on the welcome
/// screen) plus the persistent history of produced files.
struct LibraryPane: View {
    @ObservedObject var manager: DownloadManager
    @ObservedObject var library: LibraryStore
    @ObservedObject var settings: AppSettings

    @State private var query = ""
    /// Selected row: the one the spacebar previews.
    @State private var selectedID: UUID?
    @State private var spaceMonitor: Any?
    /// Entry waiting on the "move to trash" confirmation. Deleting someone's
    /// file is the one thing in this app that cannot be undone from inside it.
    @State private var trashCandidate: LibraryItem?

    private var active: [DownloadJob] { manager.activeJobs }
    private var items: [LibraryItem] { library.matching(query) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s16) {
            header

            if active.isEmpty && items.isEmpty {
                Spacer()
                EmptyState(
                    symbol: "folder",
                    title: query.isEmpty ? "Your library is empty" : "No match",
                    subtitle: query.isEmpty
                        ? "Finished downloads are displayed here, with the file kept in your destination folder."
                        : "No download matches “\(query)”."
                )
                .frame(maxWidth: .infinity)
                Spacer()
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.s20) {
                        if !active.isEmpty {
                            VStack(alignment: .leading, spacing: Theme.Space.s6) {
                                SectionHeader(title: "Downloading", count: active.count)
                                // Same cards as finished files: in a list, two
                                // different shapes for the same thing read as two
                                // different natures. Only the bar distinguishes.
                                VStack(spacing: 0) {
                                    ForEach(Array(active.enumerated()), id: \.element.id) { index, job in
                                        DownloadRow(job: job, manager: manager)
                                            .transition(.appearingCapsule)
                                        if index < active.count - 1 {
                                            Divider().overlay(Theme.separator)
                                        }
                                    }
                                }
                                .groupedCard()
                                .animation(.easeOut(duration: 0.2), value: active.map(\.id))
                            }
                        }

                        if !items.isEmpty {
                            VStack(alignment: .leading, spacing: Theme.Space.s6) {
                                SectionHeader(title: "Downloaded", count: items.count)
                                VStack(spacing: 0) {
                                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                        LibraryRow(
                                            item: item,
                                            isSelected: selectedID == item.id,
                                            onSelect: { selectedID = item.id },
                                            onDownloadAgain: { downloadAgain(item) },
                                            onRemove: { remove(item) },
                                            onTrash: { trashCandidate = item }
                                        )
                                        if index < items.count - 1 {
                                            Divider().overlay(Theme.separator)
                                        }
                                    }
                                }
                                .groupedCard()
                            }
                        }
                    }
                    .padding(.bottom, Theme.Space.s24)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .padding(.horizontal, Theme.Space.s24)
        .padding(.top, WindowChrome.trafficLightInset + Theme.Space.s16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear(perform: installSpaceMonitor)
        .onDisappear {
            if let spaceMonitor { NSEvent.removeMonitor(spaceMonitor) }
            spaceMonitor = nil
        }
        .confirmationDialog(
            "Move this download to the Trash?",
            isPresented: Binding(get: { trashCandidate != nil },
                                 set: { if !$0 { trashCandidate = nil } }),
            titleVisibility: .visible,
            presenting: trashCandidate
        ) { item in
            Button("Move to Trash", role: .destructive) { moveToTrash(item) }
            Button("Cancel", role: .cancel) { trashCandidate = nil }
        }
    }

    /// Take the entry out of the library, and register the way back.
    ///
    /// Only the entry: the file is untouched, which is exactly why undoing
    /// has to work. Removing a row is a small mistake to make and, until now,
    /// one nothing could take back.
    private func remove(_ item: LibraryItem) {
        library.removeUndoably(item) { [manager] id in manager.forget(id) }
    }

    /// The file itself, not just the entry. Goes through the Trash rather
    /// than `removeItem`: an app deleting someone's video outright, with no
    /// way back, is not a thing this one does.
    private func moveToTrash(_ item: LibraryItem) {
        trashCandidate = nil
        if item.fileExists {
            NSWorkspace.shared.recycle([item.fileURL], completionHandler: nil)
        }
        manager.forget(item.id)
    }

    /// Spacebar = preview, like in Finder.
    ///
    /// Local event monitor rather than `.onKeyPress`, which requires
    /// macOS 14 while the app targets macOS 13. Let the key through if
    /// a text field has focus, otherwise you couldn't type space in search.
    private func installSpaceMonitor() {
        guard spaceMonitor == nil else { return }
        spaceMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 49, event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty
            else { return event }
            if NSApp.keyWindow?.firstResponder is NSTextView { return event }
            guard let id = selectedID,
                  let item = library.items.first(where: { $0.id == id }),
                  item.fileExists
            else { return event }
            QuickLook.shared.toggle(item.fileURL)
            return nil
        }
    }

    /// No page title. The sidebar already names the destination, and Download
    /// and Remote Control never had one — a heading on two screens out of four
    /// read as an oversight rather than a hierarchy.
    private var header: some View {
        HStack(spacing: Theme.Space.s12) {
            Spacer()

            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.labelTertiary)
                TextField("Search", text: $query)
                    .textFieldStyle(.plain)
                    .font(Theme.Text.body)
                    .frame(width: 140)
                if !query.isEmpty {
                    IconButton(symbol: "xmark.circle.fill", size: 11, help: "Clear") { query = "" }
                }
            }
            .padding(.horizontal, Theme.Space.s8)
            .frame(height: 24)
            .background(Theme.fillTertiary, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            .opacity(library.items.isEmpty ? 0.4 : 1)
            .disabled(library.items.isEmpty)
        }
    }

    /// Restart the download with default settings of the same type: the
    /// exact original quality is not preserved in the library.
    private func downloadAgain(_ item: LibraryItem) {
        let format = DownloadFormat(
            kind: item.kind,
            videoQuality: settings.defaultVideoQuality,
            audioBitrate: settings.defaultAudioBitrate
        )
        manager.startDownload(urlString: item.sourceURL, format: format)
    }
}

// MARK: - Active Download Row

/// Same card as `LibraryRow`, plus progress: in the library, an active
/// download is just an unfinished file, not a different kind of thing.
private struct DownloadRow: View {
    let job: DownloadJob
    let manager: DownloadManager

    @State private var hovering = false

    var body: some View {
        HStack(spacing: Theme.Space.s12) {
            Thumbnail(urlString: job.thumbnailURL, width: 64, height: 36)

            VStack(alignment: .leading, spacing: 4) {
                // While the title is unknown, a neutral line instead of the
                // raw URL, which would jump to the real title later.
                if job.metadata?.title == nil {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Theme.fillSecondary)
                        .frame(width: 168, height: 9)
                        .padding(.vertical, 2)
                } else {
                    Text(job.displayTitle)
                        .font(Theme.Text.body)
                        .foregroundStyle(job.state == .paused ? Theme.labelSecondary : Theme.label)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                progressBar

                Text(meta)
                    .font(Theme.Text.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.labelSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: Theme.Space.s8)

            trailing
        }
        .padding(.horizontal, Theme.Space.s12)
        .padding(.vertical, Theme.Space.s8)
        .background(hovering ? Theme.sidebarHover : .clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .help(job.displayTitle)
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.fillTertiary)
                Capsule()
                    .fill(Theme.fillPrimary)
                    .frame(width: max(0, min(1, job.overallProgress)) * geo.size.width)
                    .animation(.easeOut(duration: 0.25), value: job.overallProgress)
            }
        }
        .frame(height: 3)
    }

    private var meta: String {
        switch job.state {
        case .queued:
            return manager.isWaiting(job) ? "Waiting…" : "Preparing…"
        case .downloading:
            // Here the card is wide: bitrate and remaining time fit,
            // unlike the welcome capsule.
            var parts = ["\(Int(job.overallProgress * 100))%"]
            let eta = Format.eta(job.progress?.eta)
            let speed = Format.speed(job.progress?.speed)
            if !eta.isEmpty { parts.append(eta) } else if !speed.isEmpty { parts.append(speed) }
            return parts.joined(separator: " · ")
        case .paused:
            return "Paused · \(Int(job.overallProgress * 100))%"
        case .merging:
            return "Finishing up…"
        default:
            return job.format.kind.label
        }
    }

    @ViewBuilder
    private var trailing: some View {
        HStack(spacing: Theme.Space.s2) {
            // Like on welcome: one affordance, cancel. The resume button
            // only shows if the job was actually paused.
            switch job.state {
            case .paused:
                IconButton(symbol: "play.circle.fill", size: 15, help: "Resume") {
                    manager.togglePause(job.id)
                }
            case .merging:
                ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 22, height: 22)
            default:
                EmptyView()
            }
            IconButton(symbol: "xmark", size: 11, help: "Cancel") { manager.cancel(job.id) }
        }
    }
}

// MARK: - Library Row

private struct LibraryRow: View {
    let item: LibraryItem
    var isSelected: Bool = false
    var onSelect: () -> Void = {}
    let onDownloadAgain: () -> Void
    let onRemove: () -> Void
    let onTrash: () -> Void

    @State private var hovering = false

    private var background: Color {
        if isSelected { return Theme.sidebarSelected }
        return hovering ? Theme.sidebarHover : .clear
    }

    var body: some View {
        HStack(spacing: Theme.Space.s12) {
            LibraryThumbnail(item: item, width: 64, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(Theme.Text.body)
                    .foregroundStyle(Theme.label)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(meta)
                    .font(Theme.Text.caption)
                    .foregroundStyle(Theme.labelSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: Theme.Space.s8)

            if !item.fileExists {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.labelSecondary)
                    .help("The file is no longer at its recorded location")
            }

            Menu {
                menuItems
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.labelSecondary)
                    .frame(width: 24, height: 22)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, Theme.Space.s12)
        .padding(.vertical, Theme.Space.s8)
        .background(background)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        // The entire row goes to the file, like the capsule on Download. The
        // same click marks the row, so the spacebar knows what to preview next.
        .onTapGesture {
            onSelect()
            guard item.fileExists else { return }
            NSWorkspace.shared.activateFileViewerSelecting([item.fileURL])
        }
        // Dragging the row drops the ACTUAL file: Finder, Messages, Mail,
        // anything that accepts a file.
        .onDrag {
            guard item.fileExists,
                  let provider = NSItemProvider(contentsOf: item.fileURL)
            else { return NSItemProvider() }
            return provider
        }
        .contextMenu { menuItems }
    }

    private var meta: String {
        var parts: [String] = []
        if let channel = item.channel, !channel.isEmpty { parts.append(channel) }
        parts.append(item.formatLabel)
        if let size = item.fileSize { parts.append(Format.bytes(size)) }
        parts.append(Self.dateFormatter.string(from: item.addedAt))
        return parts.joined(separator: " · ")
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    @ViewBuilder
    private var menuItems: some View {
        Button("Quick Look") { QuickLook.shared.toggle(item.fileURL) }
            .disabled(!item.fileExists)
        Button("Play") { FileOpener.play(item.fileURL) }
            .disabled(!item.fileExists)
        Button("Reveal in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([item.fileURL])
        }
        .disabled(!item.fileExists)
        Divider()
        Button("Copy Link") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(item.sourceURL, forType: .string)
        }
        Button("Copy Title") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(item.title, forType: .string)
        }
        Divider()
        Button("Download Again", action: onDownloadAgain)
        Divider()
        // Both halves spelled out. "Remove from Library" alone left people
        // unsure whether their file was about to disappear, and a menu is
        // read one line at a time — the answer has to be in the line itself,
        // not in the one below it.
        Button("Remove from Library (Keep File)", action: onRemove)
        Button("Move File to Trash…", action: onTrash)
            .disabled(!item.fileExists)
    }
}
