import SwiftUI
import AppKit

/// Contenu du menu de la barre des menus : état du serveur + téléchargements
/// en cours, sans avoir à ramener la fenêtre au premier plan.
struct MenuBarView: View {
    @ObservedObject var manager: DownloadManager
    @ObservedObject var server: ServerController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: server.isRunning ? "antenna.radiowaves.left.and.right" : "wifi.slash")
                Text(server.isRunning ? "Network access active" : "Server stopped")
                    .font(.subheadline.weight(.medium))
            }

            Divider()

            let active = manager.jobs.filter { $0.state == .downloading || $0.state == .queued }
            if active.isEmpty {
                Text("No active downloads")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(active) { job in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(job.displayTitle)
                            .font(.callout.weight(.medium))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if let fraction = job.progress?.fraction {
                            ProgressView(value: fraction)
                        } else {
                            ProgressView().controlSize(.small)
                        }
                    }
                }
            }

            Divider()

            HStack {
                Button("Open \(AppConfig.displayName)") {
                    NSApp.activate(ignoringOtherApps: true)
                    for window in NSApp.windows where window.canBecomeMain {
                        window.makeKeyAndOrderFront(nil)
                    }
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .font(.callout)
        }
        .padding(14)
        .frame(width: 300)
    }
}
