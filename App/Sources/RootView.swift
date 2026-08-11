// TBD — To Be Downloaded. Copyright (C) 2026 Elior Pommier.
// Licensed under the GNU AGPL v3 or later. See LICENSE and NOTICE.
import SwiftUI
import AppKit

/// The four sidebar destinations.
enum AppRoute: String, Hashable, CaseIterable, Identifiable {
    case download, library, network, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .download: return "Download"
        case .library:  return "Library"
        // "Network Access" described the mechanism; nobody could tell from it
        // what the screen was for. "Remote Control" describes the point.
        case .network:  return "Remote Control"
        case .settings: return "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .download: return "arrow.down.circle"
        case .library:  return "square.stack"
        case .network:  return "dot.radiowaves.left.and.right"
        case .settings: return "gearshape"
        }
    }

    /// The three main destinations; Settings is anchored at the bottom.
    static let primary: [AppRoute] = [.download, .library, .network]
}

/// App shell: macOS-style sidebar + detail panel.
struct RootView: View {
    @ObservedObject var manager: DownloadManager
    @ObservedObject var server: ServerController
    @ObservedObject var settings: AppSettings
    @ObservedObject var library: LibraryStore
    @ObservedObject var updater: EngineUpdater
    @ObservedObject var appUpdater: AppUpdater
    @ObservedObject var ffmpeg: FFmpegInstaller

    @State private var route: AppRoute = .download

    var body: some View {
        Group {
            if settings.onboarded {
                shell
            } else {
                // No sidebar, no destinations: there is nothing to navigate to
                // until the app can actually download something.
                OnboardingView(settings: settings, ffmpeg: ffmpeg, manager: manager)
            }
        }
        .frame(minWidth: 820, minHeight: 620)
        // The title bar is hidden, but SwiftUI still reserves its height in the
        // safe area. It ADDED to the clearance we set for the traffic lights,
        // creating a big gap above "Download". Ignoring it makes our margins
        // the only truth.
        .ignoresSafeArea(.container, edges: .top)
        .background {
            // Subtle translucency: the material takes the screen background,
            // the veil restores readability. 0.82 is where the effect still
            // shows without a busy wallpaper interfering with text.
            ZStack {
                WindowMaterial()
                Theme.window.opacity(0.82)
            }
            .ignoresSafeArea()
        }
        .task {
            // Only if the user asked for it. Launching the app opens no port:
            // that was the single most objected-to behaviour of 1.0.
            if settings.remoteControl { server.start() }
            Notifier.shared.requestAuthorization()
            library.pruneMissingFiles()
            // Downloads left off at last shutdown: we propose to resume them,
            // but don't restart automatically — closing the app can mean "stop".
            manager.loadResumable()
            settings.applyGlobalShortcut()
            // FFmpeg is NOT fetched here any more. It is a 56 MB download onto
            // someone's machine, over whatever connection they are on, and the
            // app used to start it before anyone had been asked — which is
            // exactly what the first-launch screens now put a question in front
            // of. Nothing on this path downloads without consent.
            //
            // Silent check for yt-dlp: without it, the app breaks at the next
            // YouTube bot defense. Throttled to 24 h on the updater side, and
            // has no effect if the user disabled it.
            //
            // No `refreshInstalledVersion()` here: reading the installed version
            // means launching yt-dlp (~1 s PyInstaller startup). The updater only
            // does it if it's really going to compare, and the Settings screen
            // when it appears.
            await updater.checkForUpdate(userInitiated: false)
            await appUpdater.checkForUpdate(userInitiated: false)
            // FFmpeg too, and at LAUNCH, not only in the hourly loop below.
            // It used to be checked only there, so a Mac opened and closed
            // inside an hour never updated it once — which is most of them,
            // and why people believed FFmpeg had to be updated by hand.
            await ffmpeg.checkForUpdate(userInitiated: false)

            // Then every hour: an app left open for days should keep tracking
            // yt-dlp, not just on startup. Both updaters have their own 24 h
            // throttle, so this hourly wake is usually a no-op.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_600 * 1_000_000_000)
                if Task.isCancelled { break }
                await updater.checkForUpdate(userInitiated: false)
                await appUpdater.checkForUpdate(userInitiated: false)
                // FFmpeg releases a few versions a year: daily checking costs
                // only a redirect request, and only downloads if the published
                // version changed.
                await ffmpeg.checkForUpdate(userInitiated: false)
            }
        }
        // ⌘, replaces the Settings window: the destination lives in the sidebar.
        .onReceive(NotificationCenter.default.publisher(for: .openSettingsPane)) { _ in
            route = .settings
        }
    }

    /// The app proper: sidebar plus detail panel.
    private var shell: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            detail
        }
    }

    // MARK: - Sidebar



    private var sidebar: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s2) {
            // Bare minimum to clear traffic lights (hidden title bar): they
            // physically occupy the top of the sidebar, we can't move them up.
            Spacer().frame(height: WindowChrome.trafficLightInset + Theme.Space.s2)

            ForEach(AppRoute.primary) { item in
                SidebarRow(
                    route: item,
                    isSelected: route == item,
                    badge: item == .download ? manager.activeCount : nil
                ) { route = item }
            }

            Spacer(minLength: Theme.Space.s16)

            SidebarRow(route: .settings, isSelected: route == .settings) { route = .settings }
        }
        .padding(.horizontal, Theme.Space.s8)
        .padding(.bottom, Theme.Space.s8)
        .frame(width: 210)
        .background(SidebarMaterial().ignoresSafeArea())
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        Group {
            switch route {
            case .download:
                DownloadPane(manager: manager, settings: settings, updater: updater,
                             ffmpeg: ffmpeg, library: library,
                             goToLibrary: { route = .library })
            case .library:
                LibraryPane(manager: manager, library: library, settings: settings)
            case .network:
                NetworkPane(server: server, settings: settings)
            case .settings:
                SettingsPane(settings: settings, manager: manager, server: server,
                             library: library, updater: updater, appUpdater: appUpdater,
                             ffmpeg: ffmpeg)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Background intentionally absent: it's the root's translucent material
        // showing through. A solid here would cancel it.
    }
}

// MARK: - Sidebar Row

private struct SidebarRow: View {
    let route: AppRoute
    let isSelected: Bool
    var badge: Int? = nil
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.s8) {
                Image(systemName: route.symbol)
                    .font(.system(size: 13))
                    .frame(width: 19, alignment: .center)
                Text(route.title)
                    .font(Theme.Text.body)
                Spacer(minLength: 0)
                if let badge, badge > 0 {
                    Text("\(badge)")
                        .font(Theme.Text.caption)
                        .foregroundStyle(Theme.labelSecondary)
                }
            }
            .foregroundStyle(Theme.label)
            .padding(.horizontal, Theme.Space.s8)
            .frame(height: 28)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.sidebarItem, style: .continuous)
                    .fill(background)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var background: Color {
        if isSelected { return Theme.sidebarSelected }
        return hovering ? Theme.sidebarHover : .clear
    }
}

extension Theme {
    /// `sidebar/selected` — background of the active item.
    static let sidebarSelected = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(white: 1, alpha: 0.14) : NSColor(white: 0, alpha: 0.09)
    })

    /// `sidebar/hover`


    static let sidebarHover = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(white: 1, alpha: 0.07) : NSColor(white: 0, alpha: 0.045)
    })
}
