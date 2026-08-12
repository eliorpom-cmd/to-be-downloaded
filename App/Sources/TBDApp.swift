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

    /// Route ⌘Z to whichever undo the person means.
    ///
    /// A text field being edited owns it — that is what the search field needs
    /// and it is the other thing people press ⌘Z for. Everywhere else it is
    /// the library's.
    ///
    /// The test is the first responder, not whether the responder chain
    /// accepts `undo:`: `NSWindow` answers to `undo:` whether or not it has an
    /// undo manager, so asking it first swallowed every library undo and the
    /// entry never came back. Found by removing an entry and pressing Undo.
    ///
    /// Neither item is ever disabled. Greying them out would need the state of
    /// both undo stacks at menu-build time, and focus changes do not rebuild
    /// the menu — an item that is grey when it should work is worse than one
    /// that is live when it has nothing to do.
    private func undoRedo(text selector: String, library: () -> Void) {
        if NSApp.keyWindow?.firstResponder is NSTextView {
            _ = NSApp.sendAction(Selector((selector)), to: nil, from: nil)
        } else {
            library()
        }
    }

    var body: some Scene {
        // `Window`, not `WindowGroup`: this app has one queue and one window,
        // and a group is a scene that can be instantiated more than once.
        //
        // Removing "New Window" and window tabbing was not enough. A link
        // arriving from outside — the `tbd://` scheme, the Services menu, the
        // share extension — made SwiftUI open a SECOND window on top of the
        // first, each showing the same downloads. Seen in the wild, two
        // windows at different sizes.
        Window(AppConfig.displayName, id: "main") {
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

            // ⌘Z, for taking back a library removal.
            //
            // The system items are replaced rather than added to, because
            // SwiftUI's own Undo does nothing here: a plain `WindowGroup` has
            // no undo manager, so Edit ▸ Undo was permanently grey. Typing is
            // handled first — `undo:` is offered to the responder chain, and
            // a text field being edited takes it — so the search field keeps
            // the undo people expect from a text field.
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") { undoRedo(text: "undo:", library: library.undo) }
                    .keyboardShortcut("z", modifiers: .command)
                Button("Redo") { undoRedo(text: "redo:", library: library.redo) }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
            }
        }

        // ALWAYS inserted. `MenuBarExtra(isInserted:)` looked like the right
        // way to hide it during setup and instead hangs the app: with the
        // binding false at launch, SwiftUI spins the main thread at 100 % in
        // AppDelegate.scenesDidChange → makeMainMenu, forever. Cold start,
        // no window response, accessibility answering kAXErrorNotImplemented
        // because the process never gets back to its run loop. The menu bar
        // item therefore stays, and `MenuBarView` shows nothing but a way to
        // finish setup until there is an app behind it.
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
