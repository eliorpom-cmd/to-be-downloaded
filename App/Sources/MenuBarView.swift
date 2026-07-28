import SwiftUI
import AppKit

/// Contenu du menu de la barre des menus.
///
/// Pensé comme un raccourci utile et non comme un doublon de la fenêtre : coller
/// un lien et lancer un téléchargement sans rien ouvrir, suivre ce qui tourne,
/// retrouver les derniers fichiers.
struct MenuBarView: View {
    @ObservedObject var manager: DownloadManager
    @ObservedObject var server: ServerController
    @ObservedObject var settings: AppSettings

    /// Lien YouTube présent dans le presse-papier, réévalué à l'ouverture.
    @State private var clipboardLink: String?

    private var active: [DownloadJob] { manager.activeJobs }
    private var recent: [DownloadJob] {
        Array(manager.jobs.filter { $0.state == .completed }.prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s10) {
            header

            if let link = clipboardLink {
                Button {
                    manager.startDownload(urlString: link, format: settings.currentDefaultFormat)
                    clipboardLink = nil
                } label: {
                    HStack(spacing: Theme.Space.s8) {
                        Image(systemName: "arrow.down.circle.fill").font(.system(size: 13))
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Download the copied link")
                                .font(Theme.Text.bodyEmphasized)
                            Text(shortLink(link))
                                .font(Theme.Text.caption)
                                .foregroundStyle(Theme.labelSecondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, Theme.Space.s10)
                    .padding(.vertical, Theme.Space.s8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.fillTertiary,
                                in: RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if !active.isEmpty {
                section("Downloading") {
                    ForEach(active) { job in
                        row(job)
                    }
                }
            }

            if !recent.isEmpty {
                section("Recent") {
                    ForEach(recent) { job in
                        Button {
                            if let url = job.fileURL {
                                NSWorkspace.shared.activateFileViewerSelecting([url])
                            }
                        } label: {
                            HStack(spacing: Theme.Space.s8) {
                                Image(systemName: "checkmark.circle")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.labelSecondary)
                                Text(job.displayTitle)
                                    .font(Theme.Text.body)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Show in Finder")
                    }
                }
            }

            Divider()

            HStack(spacing: Theme.Space.s12) {
                // Le sigle : la fenêtre de la barre des menus est étroite et
                // ce bouton partage sa ligne avec Quit.
                Button("Open \(AppConfig.shortName)", action: openMainWindow)
                Spacer(minLength: 0)
                Button("Quit") { NSApp.terminate(nil) }
            }
            .font(Theme.Text.body)
        }
        .padding(Theme.Space.s12)
        .frame(width: 300)
        .task { refreshClipboard() }
    }

    // MARK: - Morceaux

    private var header: some View {
        HStack(spacing: Theme.Space.s8) {
            Image(systemName: server.isRunning
                  ? "antenna.radiowaves.left.and.right" : "wifi.slash")
                .font(.system(size: 12))
                .foregroundStyle(Theme.labelSecondary)
            Text(server.url ?? "Network access off")
                .font(Theme.Text.caption)
                .foregroundStyle(Theme.labelSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if let url = server.url {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc").font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.labelSecondary)
                .help("Copy the address")
            }
        }
    }

    private func section<Content: View>(
        _ title: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s6) {
            SectionHeader(title: title)
            content()
        }
    }

    private func row(_ job: DownloadJob) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: Theme.Space.s8) {
                Text(job.displayTitle)
                    .font(Theme.Text.body)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: Theme.Space.s8)
                Text("\(Int(job.overallProgress * 100))%")
                    .font(Theme.Text.caption)
                    .foregroundStyle(Theme.labelSecondary)
                    .monospacedDigit()
                IconButton(symbol: job.state == .paused ? "play.fill" : "pause.fill",
                           size: 9, help: job.state == .paused ? "Resume" : "Pause") {
                    manager.togglePause(job.id)
                }
                IconButton(symbol: "xmark", size: 9, help: "Cancel") {
                    manager.cancel(job.id)
                }
            }
            // Une seule barre, la même que dans la fenêtre.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.fillTertiary)
                    Capsule().fill(Theme.ink)
                        .frame(width: max(0, min(1, job.overallProgress)) * geo.size.width)
                        .animation(.easeOut(duration: 0.25), value: job.overallProgress)
                }
            }
            .frame(height: 3)
        }
    }

    // MARK: - Actions

    private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.canBecomeMain {
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func refreshClipboard() {
        guard let copied = NSPasteboard.general.string(forType: .string),
              YouTubeLink.isValid(copied) else {
            clipboardLink = nil
            return
        }
        clipboardLink = copied.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func shortLink(_ raw: String) -> String {
        raw.replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "www.", with: "")
    }
}
