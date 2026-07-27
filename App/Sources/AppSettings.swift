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
        static let audioFormat = "defaultAudioFormat"
        static let subtitles = "embedSubtitles"
        static let maxConcurrent = "maxConcurrentDownloads"
        static let filenameTemplate = "filenameTemplate"
        static let filenameCustom = "filenameCustomPattern"
        static let globalShortcut = "globalShortcutEnabled"
        static let shortcutKeyCode = "globalShortcutKeyCode"
        static let shortcutModifiers = "globalShortcutModifiers"
        static let shortcutLabel = "globalShortcutLabel"
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
    /// Conteneur audio produit (M4A sans ré-encodage par défaut).
    @Published var audioFormat: AudioFormat {
        didSet { store.set(audioFormat.rawValue, forKey: Key.audioFormat) }
    }
    /// Incruster les sous-titres dans les vidéos.
    @Published var embedSubtitles: Bool {
        didSet { store.set(embedSubtitles, forKey: Key.subtitles) }
    }
    /// Téléchargements menés de front. Au-delà, ils attendent leur tour.
    ///
    /// Deux par défaut : lancer dix téléchargements en même temps ne va pas
    /// plus vite — la bande passante est la même — mais retarde le premier
    /// fichier utilisable et rend tous les temps restants faux.
    @Published var maxConcurrent: Int {
        didSet { store.set(maxConcurrent, forKey: Key.maxConcurrent) }
    }
    @Published var filenameTemplate: FilenameTemplate {
        didSet { store.set(filenameTemplate.rawValue, forKey: Key.filenameTemplate) }
    }
    @Published var filenameCustom: String {
        didSet { store.set(filenameCustom, forKey: Key.filenameCustom) }
    }
    /// Raccourci global ⌥⌘V : coller et télécharger sans passer par la fenêtre.
    @Published var globalShortcut: Bool {
        didSet {
            store.set(globalShortcut, forKey: Key.globalShortcut)
            applyGlobalShortcut()
        }
    }
    @Published private(set) var shortcutKeyCode: Int
    @Published private(set) var shortcutModifiers: UInt
    @Published private(set) var shortcutLabel: String
    /// Vrai quand la dernière combinaison demandée a été refusée par le
    /// système — presque toujours parce qu'une autre app l'a déjà prise.
    @Published private(set) var shortcutRejected = false

    /// Change la combinaison. Renvoie `false` si elle est déjà prise, auquel
    /// cas l'ancienne est remise en place.
    @discardableResult
    func setShortcut(keyCode: Int, modifiers: UInt, label: String) -> Bool {
        let previous = (shortcutKeyCode, shortcutModifiers, shortcutLabel)
        shortcutKeyCode = keyCode
        shortcutModifiers = modifiers
        shortcutLabel = label
        store.set(keyCode, forKey: Key.shortcutKeyCode)
        store.set(Int(modifiers), forKey: Key.shortcutModifiers)
        store.set(label, forKey: Key.shortcutLabel)

        guard globalShortcut else { return true }
        if applyGlobalShortcut() { return true }
        // Refusée : on ne laisse pas l'utilisateur avec un raccourci mort.
        shortcutKeyCode = previous.0
        shortcutModifiers = previous.1
        shortcutLabel = previous.2
        store.set(previous.0, forKey: Key.shortcutKeyCode)
        store.set(Int(previous.1), forKey: Key.shortcutModifiers)
        store.set(previous.2, forKey: Key.shortcutLabel)
        _ = applyGlobalShortcut()
        shortcutRejected = true
        return false
    }

    func clearShortcutRejection() { shortcutRejected = false }

    @discardableResult
    func applyGlobalShortcut() -> Bool {
        guard globalShortcut else {
            GlobalShortcut.disable()
            shortcutRejected = false
            return true
        }
        let ok = GlobalShortcut.enable(keyCode: shortcutKeyCode, modifiers: shortcutModifiers)
        shortcutRejected = !ok
        return ok
    }

    /// Motif `-o` effectif, extension comprise.
    var outputPattern: String {
        FilenameTemplate.outputPattern(filenameTemplate, custom: filenameCustom)
    }

    /// Langues de sous-titres demandées : celle du système d'abord, puis
    /// l'anglais — la seule qu'on retrouve à peu près partout.
    var subtitleLanguages: [String] {
        let system = Locale.current.language.languageCode?.identifier ?? "en"
        return system == "en" ? ["en"] : [system, "en"]
    }

    /// Format correspondant aux réglages par défaut, pour les déclencheurs qui
    /// n'ont pas d'UI de choix (menu de la barre des menus, ⌘⇧V).
    var currentDefaultFormat: DownloadFormat {
        DownloadFormat(kind: defaultKind,
                       videoQuality: defaultVideoQuality,
                       audioBitrate: defaultAudioBitrate,
                       audioFormat: audioFormat,
                       subtitles: embedSubtitles)
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

        audioFormat = AudioFormat(rawValue: store.string(forKey: Key.audioFormat) ?? "") ?? .m4a
        embedSubtitles = store.object(forKey: Key.subtitles) as? Bool ?? false
        maxConcurrent = min(max(store.object(forKey: Key.maxConcurrent) as? Int ?? 2, 1), 5)
        filenameTemplate = FilenameTemplate(
            rawValue: store.string(forKey: Key.filenameTemplate) ?? "") ?? .title
        filenameCustom = store.string(forKey: Key.filenameCustom) ?? "%(title)s"
        globalShortcut = store.object(forKey: Key.globalShortcut) as? Bool ?? false
        shortcutKeyCode = store.object(forKey: Key.shortcutKeyCode) as? Int
            ?? GlobalShortcut.defaultKeyCode
        shortcutModifiers = UInt(store.object(forKey: Key.shortcutModifiers) as? Int
            ?? Int(GlobalShortcut.defaultModifiers))
        shortcutLabel = store.string(forKey: Key.shortcutLabel) ?? GlobalShortcut.defaultLabel
    }
}
