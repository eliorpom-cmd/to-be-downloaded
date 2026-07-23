import SwiftUI
import AppKit

/// Fenêtre Réglages (⌘,) : dossier de sortie, format par défaut, port du serveur.
struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    let manager: DownloadManager
    let server: ServerController

    @State private var portText: String = ""

    var body: some View {
        Form {
            Section("Downloads") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Destination folder")
                        Text(settings.outputDirectory.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Button("Choose…", action: chooseFolder)
                }

                Picker("Default format", selection: $settings.defaultKind) {
                    ForEach(MediaKind.allCases) { Text($0.label).tag($0) }
                }
                Picker("Default video quality", selection: $settings.defaultVideoQuality) {
                    ForEach(VideoQuality.allCases) { Text($0.label).tag($0) }
                }
                Picker("Default audio bitrate", selection: $settings.defaultAudioBitrate) {
                    ForEach(AudioBitrate.allCases) { Text($0.label).tag($0) }
                }
            }

            Section("Appearance") {
                Picker("Theme", selection: $settings.appearance) {
                    ForEach(AppearancePreference.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section("Network") {
                HStack {
                    TextField("Port", text: $portText)
                        .frame(width: 90)
                        .onSubmit(applyPort)
                    Button("Apply & restart", action: applyPort)
                        .disabled(UInt16(portText) == nil || UInt16(portText) == settings.port)
                    Spacer()
                }
                if let url = server.url {
                    Text("Serving at \(url)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .onAppear { portText = String(settings.port) }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = settings.outputDirectory
        if panel.runModal() == .OK, let url = panel.url {
            settings.outputDirectory = url
            manager.reconfigure()
        }
    }

    private func applyPort() {
        guard let p = UInt16(portText), p != settings.port else { return }
        settings.port = p
        server.restart()
    }
}
