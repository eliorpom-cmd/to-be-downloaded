// TBD — To be downloaded. Copyright (C) 2026 Elior Pommier.
// Licensed under the GNU AGPL v3 or later. See LICENSE and NOTICE.
import SwiftUI

/// Choose which videos to take from a playlist.
///
/// It only opens if the link designates one. Previously, `--no-playlist`
/// was hardcoded: pasting a playlist would download the first video
/// without saying so, the worst behavior — silent and wrong.
struct PlaylistSheet: View {
    let playlist: Playlist
    /// Specific video targeted by the link, when it designates one
    /// (`watch?v=…&list=…`). This is the ambiguous case that justifies asking.
    let focusedVideoID: String?
    let onDownload: ([Playlist.Entry]) -> Void
    let onCancel: () -> Void

    @State private var selection: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(Theme.separator)
            list
            Divider().overlay(Theme.separator)
            footer
        }
        .frame(width: 460, height: 480)
        .background(Theme.window)
        .onAppear { selection = Set(playlist.entries.map(\.id)) }
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s2) {
            Text(playlist.title)
                .font(Theme.Text.title3)
                .foregroundStyle(Theme.label)
                .lineLimit(2)
            Text("\(playlist.entries.count) videos in this playlist")
                .font(Theme.Text.caption)
                .foregroundStyle(Theme.labelSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Space.s16)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(playlist.entries) { entry in
                    row(entry)
                    Divider().overlay(Theme.separator).padding(.leading, 78)
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func row(_ entry: Playlist.Entry) -> some View {
        let isOn = selection.contains(entry.id)
        return HStack(spacing: Theme.Space.s10) {
            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 15))
                .foregroundStyle(isOn ? Theme.label : Theme.labelTertiary)

            Thumbnail(urlString: entry.thumbnailURL, width: 48, height: 27)

            Text(entry.title)
                .font(Theme.Text.body)
                .foregroundStyle(Theme.label)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Spacer(minLength: Theme.Space.s8)

            if let duration = entry.duration, duration > 0 {
                Text(Format.duration(duration))
                    .font(Theme.Text.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.labelSecondary)
            }
        }
        .padding(.horizontal, Theme.Space.s16)
        .padding(.vertical, Theme.Space.s8)
        .contentShape(Rectangle())
        .onTapGesture {
            if isOn { selection.remove(entry.id) } else { selection.insert(entry.id) }
        }
    }

    private var footer: some View {
        HStack(spacing: Theme.Space.s8) {
            Button(selection.count == playlist.entries.count ? "Deselect All" : "Select All") {
                selection = selection.count == playlist.entries.count
                    ? []
                    : Set(playlist.entries.map(\.id))
            }
            .buttonStyle(.push)

            // Shortcut for the common case: clicked a video, it was in a
            // playlist, only that one was wanted.
            if let focusedVideoID,
               let entry = playlist.entries.first(where: { $0.id == focusedVideoID }) {
                Button("This Video Only") { onDownload([entry]) }
                    .buttonStyle(.push)
            }

            Spacer(minLength: Theme.Space.s8)

            Button("Cancel", action: onCancel)
                .buttonStyle(.push)
                .keyboardShortcut(.cancelAction)

            Button(selection.count == 1 ? "Download 1 Video"
                                        : "Download \(selection.count) Videos") {
                onDownload(playlist.entries.filter { selection.contains($0.id) })
            }
            .buttonStyle(.primaryCapsule)
            .disabled(selection.isEmpty)
            .keyboardShortcut(.defaultAction)
        }
        .padding(Theme.Space.s12)
    }
}
