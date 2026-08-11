// TBD — To be downloaded. Copyright (C) 2026 Elior Pommier.
// Licensed under the GNU AGPL v3 or later. See LICENSE and NOTICE.
import SwiftUI
import AppKit

/// App appearance preference, independent of system settings.
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

    /// SF Symbol for the toggle button (reflects current state).
    var symbol: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light:  return "sun.max.fill"
        case .dark:   return "moon.fill"
        }
    }

    /// `nil` = follows system; otherwise forces light/dark.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

/// Persisted preferences (UserDefaults): output folder, default format,
/// server port, appearance. Changes are applied explicitly by
/// the views (engine rebuild / server restart).
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
        static let onboarded = "onboardingCompleted"
        static let remoteControl = "remoteControlEnabled"
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

    /// Apply appearance to the entire application.
    ///
    /// Goes through `NSApp.appearance` not `.preferredColorScheme`: once a
    /// SwiftUI window is forced to light or dark, passing `nil` does NOT
    /// take it back to system settings — it stays frozen.
    /// `NSApp.appearance = nil` does.
    static func applyAppearance(_ preference: AppearancePreference) {
        let appearance: NSAppearance?
        switch preference {
        case .system: appearance = nil
        case .light:  appearance = NSAppearance(named: .aqua)
        case .dark:   appearance = NSAppearance(named: .darkAqua)
        }
        NSApplication.shared.appearance = appearance
    }
    /// yt-dlp channel tracked by the update mechanism.
    @Published var updateChannel: UpdateChannel {
        didSet { store.set(updateChannel.rawValue, forKey: Key.updateChannel) }
    }
    /// Daily check on launch, then hourly while the app runs. On by default:
    /// without it, the app breaks at the next YouTube bot defense.
    @Published var autoUpdateEngine: Bool {
        didSet { store.set(autoUpdateEngine, forKey: Key.autoUpdateEngine) }
    }
    /// Automatic update of the app itself (signed GitHub releases).
    @Published var autoUpdateApp: Bool {
        didSet { store.set(autoUpdateApp, forKey: Key.autoUpdateApp) }
    }
    /// Audio container produced (M4A no re-encoding by default).
    @Published var audioFormat: AudioFormat {
        didSet { store.set(audioFormat.rawValue, forKey: Key.audioFormat) }
    }
    /// Embed subtitles in videos.
    @Published var embedSubtitles: Bool {
        didSet { store.set(embedSubtitles, forKey: Key.subtitles) }
    }
    /// Concurrent downloads. Beyond that, they wait their turn.
    ///
    /// Two by default: launching ten downloads at once is no faster —
    /// bandwidth is the same — but delays the first usable file and makes
    /// all remaining times wrong.
    @Published var maxConcurrent: Int {
        didSet { store.set(maxConcurrent, forKey: Key.maxConcurrent) }
    }
    @Published var filenameTemplate: FilenameTemplate {
        didSet { store.set(filenameTemplate.rawValue, forKey: Key.filenameTemplate) }
    }
    @Published var filenameCustom: String {
        didSet { store.set(filenameCustom, forKey: Key.filenameCustom) }
    }
    /// Has the first-launch walkthrough been through? Until it has, the app
    /// downloads nothing and assumes nothing about where files should go.
    @Published var onboarded: Bool {
        didSet { store.set(onboarded, forKey: Key.onboarded) }
    }
    /// Whether the LAN server may run at all.
    ///
    /// **Off by default, and deliberately.** The app used to open a port on
    /// the user's machine the moment it launched, without asking — which
    /// several people objected to, reasonably. Remote control is now
    /// something you turn on, and the choice is remembered.
    ///
    /// Written by the buttons on the Remote Control screen, never by
    /// `ServerController.stop()`: Settings stops the server before an update
    /// relaunch, and a port change stops then starts it. Persisting from
    /// `stop()` would have the app conclude "the user turned it off" after
    /// every update.
    @Published var remoteControl: Bool {
        didSet { store.set(remoteControl, forKey: Key.remoteControl) }
    }
    /// Global shortcut ⌥⌘V: paste and download without opening the window.
    @Published var globalShortcut: Bool {
        didSet {
            store.set(globalShortcut, forKey: Key.globalShortcut)
            applyGlobalShortcut()
        }
    }
    @Published private(set) var shortcutKeyCode: Int
    @Published private(set) var shortcutModifiers: UInt
    @Published private(set) var shortcutLabel: String
    /// True when the last requested combo was rejected by the system —
    /// almost always because another app already took it.
    @Published private(set) var shortcutRejected = false

    /// Change the combo. Returns `false` if it's already taken, in which
    /// case the old one is restored.
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
        // Rejected: don't leave the user with a dead shortcut.
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

    /// Effective `-o` pattern, extension included.
    var outputPattern: String {
        FilenameTemplate.outputPattern(filenameTemplate, custom: filenameCustom)
    }

    /// Requested subtitle languages: system language first, then English —
    /// the only one found almost everywhere.
    var subtitleLanguages: [String] {
        let system = Locale.current.language.languageCode?.identifier ?? "en"
        return system == "en" ? ["en"] : [system, "en"]
    }

    /// Format matching default settings, for triggers without choice UI
    /// (menu bar menu, ⌘⇧V).
    var currentDefaultFormat: DownloadFormat {
        DownloadFormat(kind: defaultKind,
                       videoQuality: defaultVideoQuality,
                       audioBitrate: defaultAudioBitrate,
                       audioFormat: audioFormat,
                       subtitles: embedSubtitles)
    }

    /// Cycle through System → Light → Dark → System (header toggle button).
    func cycleAppearance() {
        let all = AppearancePreference.allCases
        let next = (all.firstIndex(of: appearance).map { $0 + 1 } ?? 0) % all.count
        appearance = all[next]
    }

    private init() {
        // Output folder
        if let path = store.string(forKey: Key.output), !path.isEmpty {
            outputDirectory = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            // Straight to ~/Downloads: no subfolder named after the app,
            // files land where people look for them.
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
        // Anyone upgrading from 1.0 already has a working app and a folder
        // they chose (or accepted): walking them through setup would be
        // asking questions that were answered months ago. An existing
        // FFmpeg is the tell.
        onboarded = store.object(forKey: Key.onboarded) as? Bool
            ?? BinaryLocator.hasManagedFFmpeg
        remoteControl = store.object(forKey: Key.remoteControl) as? Bool ?? false
        globalShortcut = store.object(forKey: Key.globalShortcut) as? Bool ?? false
        shortcutKeyCode = store.object(forKey: Key.shortcutKeyCode) as? Int
            ?? GlobalShortcut.defaultKeyCode
        shortcutModifiers = UInt(store.object(forKey: Key.shortcutModifiers) as? Int
            ?? Int(GlobalShortcut.defaultModifiers))
        shortcutLabel = store.string(forKey: Key.shortcutLabel) ?? GlobalShortcut.defaultLabel
    }
}
