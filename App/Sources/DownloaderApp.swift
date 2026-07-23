import SwiftUI

extension Notification.Name {
    static let focusURLField = Notification.Name("focusURLField")
    static let pasteAndDownload = Notification.Name("pasteAndDownload")
}

@main
struct DownloaderApp: App {
    @StateObject private var manager: DownloadManager
    @StateObject private var server: ServerController
    @StateObject private var settings = AppSettings.shared

    init() {
        let downloads = DownloadManager()
        _manager = StateObject(wrappedValue: downloads)
        _server = StateObject(wrappedValue: ServerController(downloads: downloads))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(manager: manager, server: server, settings: settings)
                .tint(Theme.ink)
                .preferredColorScheme(settings.appearance.colorScheme)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 860, height: 720)
        .commands {
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
            MenuBarView(manager: manager, server: server)
                .preferredColorScheme(settings.appearance.colorScheme)
        } label: {
            Image(systemName: manager.activeCount > 0 ? "arrow.down.circle.fill" : "arrow.down.circle")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(settings: settings, manager: manager, server: server)
                .preferredColorScheme(settings.appearance.colorScheme)
        }
    }
}
