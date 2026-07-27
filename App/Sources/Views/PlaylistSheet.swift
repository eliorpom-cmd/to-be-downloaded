import SwiftUI

/// Choix des vidéos à prendre dans une playlist.
///
/// Elle ne s'ouvre QUE si le lien en désigne une. Auparavant, `--no-playlist`
/// était câblé en dur : coller une playlist téléchargeait la première vidéo
/// sans le dire, ce qui est le pire des comportements — silencieux et faux.
struct PlaylistSheet: View {
    let playlist: Playlist
    /// Vidéo précise visée par le lien, quand il en désigne une
    /// (`watch?v=…&list=…`). C'est le cas ambigu qui justifie la question.
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

    // MARK: - Morceaux

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

            // Raccourci du cas courant : on a cliqué une vidéo, elle
            // appartenait à une playlist, on ne voulait qu'elle.
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
