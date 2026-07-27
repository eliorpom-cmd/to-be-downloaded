import SwiftUI
import AppKit

/// Préférence d'apparence de l'app, indépendante du réglage système.
enum AppearancePreference: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    /// SF Symbol du bouton bascule (reflète l'état courant).
    var symbol: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light:  return "sun.max.fill"
        case .dark:   return "moon.fill"
        }
    }

    /// `nil` = suit le système ; sinon force clair/sombre.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

/// Préférences persistées (UserDefaults) : dossier de sortie, format par défaut,
/// port du serveur, apparence. Les changements sont appliqués explicitement par
/// les vues (rebuild du moteur / redémarrage du serveur).
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let store = UserDefaults.standard
    private enum Key {
        static let output = "outputDirectoryPath"
        static let kind = "defaultKind"
        static let videoQuality = "defaultVideoQuality"
        static let audioBitrate = "defaultAudioBitrate"
        static let port = "serverPort"
        static let appearance = "appearancePreference"
        static let updateChannel = "ytDlpUpdateChannel"
        static let autoUpdateEngine = "ytDlpAutoUpdate"
        static let autoUpdateApp = "appAutoUpdate"
    }

    @Published var outputDirectory: URL {
        didSet { store.set(outputDirectory.path, forKey: Key.output) }
    }
    @Published var defaultKind: MediaKind {
        didSet { store.set(defaultKind.rawValue, forKey: Key.kind) }
    }
    @Published var defaultVideoQuality: VideoQuality {
        didSet { store.set(defaultVideoQuality.rawValue, forKey: Key.videoQuality) }
    }
    @Published var defaultAudioBitrate: AudioBitrate {
        didSet { store.set(defaultAudioBitrate.rawValue, forKey: Key.audioBitrate) }
    }
    @Published var port: UInt16 {
        didSet { store.set(Int(port), forKey: Key.port) }
    }
    @Published var appearance: AppearancePreference {
        didSet {
            store.set(appearance.rawValue, forKey: Key.appearance)
            Self.applyAppearance(appearance)
        }
    }

    /// Applique l'apparence à l'application entière.
    ///
    /// On passe par `NSApp.appearance` et NON par `.preferredColorScheme` :
    /// une fois qu'une fenêtre SwiftUI a été forcée en clair ou en sombre,
    /// repasser `nil` ne la rend PAS au réglage système — elle reste figée.
    /// `NSApp.appearance = nil` le fait, lui.
    static func applyAppearance(_ preference: AppearancePreference) {
        let appearance: NSAppearance?
        switch preference {
        case .system: appearance = nil
        case .light:  appearance = NSAppearance(named: .aqua)
        case .dark:   appearance = NSAppearance(named: .darkAqua)
        }
        NSApplication.shared.appearance = appearance
    }
    /// Canal yt-dlp suivi par le mécanisme de mise à jour.
    @Published var updateChannel: UpdateChannel {
        didSet { store.set(updateChannel.rawValue, forKey: Key.updateChannel) }
    }
    /// Vérification quotidienne, au lancement puis toutes les heures tant que
    /// l'app tourne. Activée par défaut : sans elle, l'app casse dès la
    /// prochaine parade anti-bot de YouTube.
    @Published var autoUpdateEngine: Bool {
        didSet { store.set(autoUpdateEngine, forKey: Key.autoUpdateEngine) }
    }
    /// Mise à jour automatique de l'app elle-même (releases GitHub signées).
    @Published var autoUpdateApp: Bool {
        didSet { store.set(autoUpdateApp, forKey: Key.autoUpdateApp) }
    }

    /// Format correspondant aux réglages par défaut, pour les déclencheurs qui
    /// n'ont pas d'UI de choix (menu de la barre des menus, ⌘⇧V).
    var currentDefaultFormat: DownloadFormat {
        DownloadFormat(kind: defaultKind,
                       videoQuality: defaultVideoQuality,
                       audioBitrate: defaultAudioBitrate)
    }

    /// Fait défiler Système → Clair → Sombre → Système (bouton bascule du header).
    func cycleAppearance() {
        let all = AppearancePreference.allCases
        let next = (all.firstIndex(of: appearance).map { $0 + 1 } ?? 0) % all.count
        appearance = all[next]
    }

    private init() {
        // Dossier de sortie
        if let path = store.string(forKey: Key.output), !path.isEmpty {
            outputDirectory = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            // Directement ~/Downloads : pas de sous-dossier au nom de l'app,
            // les fichiers atterrissent là où les gens les cherchent.
            outputDirectory = FileManager.default
                .urls(for: .downloadsDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Downloads", isDirectory: true)
        }

        defaultKind = MediaKind(rawValue: store.string(forKey: Key.kind) ?? "") ?? .video
        defaultVideoQuality = VideoQuality(rawValue: store.object(forKey: Key.videoQuality) as? Int ?? 1080) ?? .p1080
        defaultAudioBitrate = AudioBitrate(rawValue: store.object(forKey: Key.audioBitrate) as? Int ?? 192) ?? .k192

        let storedPort = store.object(forKey: Key.port) as? Int
        port = UInt16(storedPort ?? Int(AppConfig.defaultPort))

        appearance = AppearancePreference(rawValue: store.string(forKey: Key.appearance) ?? "") ?? .system

        updateChannel = UpdateChannel(rawValue: store.string(forKey: Key.updateChannel) ?? "") ?? .stable
        autoUpdateEngine = store.object(forKey: Key.autoUpdateEngine) as? Bool ?? true
        autoUpdateApp = store.object(forKey: Key.autoUpdateApp) as? Bool ?? true
    }
}
