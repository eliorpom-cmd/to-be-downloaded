import SwiftUI
import AppKit

/// Les quatre destinations de la sidebar.
enum AppRoute: String, Hashable, CaseIterable, Identifiable {
    case download, library, network, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .download: return "Download"
        case .library:  return "Library"
        case .network:  return "Network Access"
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

    /// Les trois destinations principales ; Settings est ancré en bas.
    static let primary: [AppRoute] = [.download, .library, .network]
}

/// Coquille de l'app : sidebar façon macOS + panneau de détail.
struct RootView: View {
    @ObservedObject var manager: DownloadManager
    @ObservedObject var server: ServerController
    @ObservedObject var settings: AppSettings
    @ObservedObject var library: LibraryStore
    @ObservedObject var updater: EngineUpdater
    @ObservedObject var appUpdater: AppUpdater

    @State private var route: AppRoute = .download

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            detail
        }
        .frame(minWidth: 820, minHeight: 620)
        // La barre de titre est masquée, mais SwiftUI continue d'en réserver la
        // hauteur en zone sûre. Elle s'AJOUTAIT au dégagement qu'on pose
        // nous-mêmes pour les feux tricolores, d'où le grand vide au-dessus de
        // « Download ». En l'ignorant, nos marges redeviennent la seule vérité.
        .ignoresSafeArea(.container, edges: .top)
        .background(Theme.window)
        .task {
            server.start()
            Notifier.shared.requestAuthorization()
            library.pruneMissingFiles()
            // Téléchargements laissés en plan au dernier arrêt : on les propose,
            // on ne les relance pas — fermer l'app peut vouloir dire « stop ».
            manager.loadResumable()
            GlobalShortcut.setEnabled(settings.globalShortcut)
            // Contrôle silencieux de yt-dlp : sans lui, l'app casse à la
            // prochaine parade anti-bot de YouTube. Throttlé à 24 h côté
            // updater, et sans effet si l'utilisateur l'a désactivé.
            //
            // Pas de `refreshInstalledVersion()` ici : lire la version installée
            // veut dire lancer yt-dlp (~1 s de démarrage PyInstaller). L'updater
            // ne le fait que s'il va vraiment comparer, et l'écran Réglages
            // quand il s'affiche.
            await updater.checkForUpdate(userInitiated: false)
            await appUpdater.checkForUpdate(userInitiated: false)

            // Puis toutes les heures : une app laissée ouverte plusieurs jours
            // doit continuer à suivre yt-dlp, pas seulement au démarrage. Les
            // deux updaters portent leur propre throttle de 24 h, ce réveil
            // horaire est donc quasi toujours un no-op.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_600 * 1_000_000_000)
                if Task.isCancelled { break }
                await updater.checkForUpdate(userInitiated: false)
                await appUpdater.checkForUpdate(userInitiated: false)
            }
        }
        // ⌘, remplace la fenêtre Réglages : la destination vit dans la sidebar.
        .onReceive(NotificationCenter.default.publisher(for: .openSettingsPane)) { _ in
            route = .settings
        }
        // ⌘L et ⌘⇧V ramènent forcément sur l'écran de téléchargement.
        .onReceive(NotificationCenter.default.publisher(for: .focusURLField)) { _ in
            route = .download
        }
        .onReceive(NotificationCenter.default.publisher(for: .pasteAndDownload)) { _ in
            route = .download
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s2) {
            // Strict nécessaire pour dégager les feux tricolores (barre de titre
            // masquée) : ils occupent physiquement le haut de la sidebar, on ne
            // peut pas les remonter plus haut.
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
                             library: library, goToLibrary: { route = .library })
            case .library:
                LibraryPane(manager: manager, library: library, settings: settings)
            case .network:
                NetworkPane(server: server, settings: settings)
            case .settings:
                SettingsPane(settings: settings, manager: manager, server: server,
                             library: library, updater: updater, appUpdater: appUpdater)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.window)
    }
}

// MARK: - Ligne de sidebar

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
    /// `sidebar/selected` — fond de l'élément actif.
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
