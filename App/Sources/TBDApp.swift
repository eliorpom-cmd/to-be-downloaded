import SwiftUI

extension Notification.Name {
    static let focusURLField = Notification.Name("focusURLField")
    static let pasteAndDownload = Notification.Name("pasteAndDownload")
    /// ⌘, : settings live in the sidebar, not a separate window.
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
                // No `.preferredColorScheme`: appearance is driven by NSApp
                // (see AppSettings.applyAppearance), the only way to truly
                // go back to system settings.
                .task { AppSettings.applyAppearance(settings.appearance) }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1000, height: 680)
        .commands {
            // Replace the system "Settings…" item: select the Settings
            // destination in the sidebar instead of opening a window.
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
            // The app icon — the full tile, the one from Dock — not a generic
            // symbol, as a template image to follow the menu bar theme.
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
