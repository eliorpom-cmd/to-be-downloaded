// TBD — To Be Downloaded. Copyright (C) 2026 Elior Pommier.
// Licensed under the GNU AGPL v3 or later. See LICENSE and NOTICE.
import SwiftUI

extension Notification.Name {
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

            // No "New Window": a second window would show the same single
            // download queue, and macOS then folds the two into tabs — a title
            // bar full of tabs for one app that has one state. Replacing the
            // group with nothing removes ⌘N along with the menu item.
            //
            // Nothing takes its place. "Focus URL Field" (⌘L) and "Paste and
            // Download" (⌘⇧V) used to live here: the field is already focused
            // when the window opens, and pasting is what the ⌥⌘V system-wide
            // shortcut in Settings is for — from inside the app, ⌘V then Return
            // does the same in the same number of keys.
            CommandGroup(replacing: .newItem) {}
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
