import SwiftUI

extension Notification.Name {
    static let focusURLField = Notification.Name("focusURLField")
    static let pasteAndDownload = Notification.Name("pasteAndDownload")
    /// ⌘, : les réglages vivent dans la sidebar, pas dans une fenêtre à part.
    static let openSettingsPane = Notification.Name("openSettingsPane")
}

@main
struct TBDApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var manager: DownloadManager
    @StateObject private var server: ServerController
    @StateObject private var library: LibraryStore
    @StateObject private var settings = AppSettings.shared
    @StateObject private var updater = EngineUpdater()
    @StateObject private var appUpdater = AppUpdater()
    @StateObject private var ffmpeg = FFmpegInstaller()

    init() {
        let store = LibraryStore()
        let downloads = DownloadManager(library: store)
        _library = StateObject(wrappedValue: store)
        _manager = StateObject(wrappedValue: downloads)
        _server = StateObject(wrappedValue: ServerController(downloads: downloads))
    }

    var body: some Scene {
        WindowGroup {
            RootView(manager: manager, server: server, settings: settings,
                     library: library, updater: updater, appUpdater: appUpdater,
                     ffmpeg: ffmpeg)
                .tint(Theme.ink)
                // Pas de `.preferredColorScheme` : l'apparence est pilotée par
                // NSApp (cf. AppSettings.applyAppearance), seul moyen de
                // revenir réellement au réglage système.
                .task { AppSettings.applyAppearance(settings.appearance) }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1000, height: 680)
        .commands {
            // Remplace l'élément « Settings… » système : il sélectionne la
            // destination Settings de la sidebar au lieu d'ouvrir une fenêtre.
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    NotificationCenter.default.post(name: .openSettingsPane, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            CommandGroup(after: .newItem) {
                Button("Focus URL Field") {
                    NotificationCenter.default.post(name: .focusURLField, object: nil)
                }
                .keyboardShortcut("l", modifiers: .command)

                Button("Paste and Download") {
                    NotificationCenter.default.post(name: .pasteAndDownload, object: nil)
                }
                .keyboardShortcut("v", modifiers: [.command, .shift])
            }
        }

        MenuBarExtra {
            MenuBarView(manager: manager, server: server, settings: settings)
        } label: {
            // L'icône de l'app plutôt qu'un symbole générique, en image template
            // pour suivre le thème de la barre des menus.
            HStack(spacing: 3) {
                Image(nsImage: MascotImage.menuBar())
                if manager.activeCount > 0 {
                    Text("\(manager.activeCount)").monospacedDigit()
                }
            }
        }
        .menuBarExtraStyle(.window)
    }
}
