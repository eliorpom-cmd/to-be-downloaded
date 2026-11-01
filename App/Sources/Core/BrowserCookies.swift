// TBD — To Be Downloaded. Copyright (C) 2026 Elior Pommier.
// Licensed under the GNU AGPL v3 or later. See LICENSE and NOTICE.
import Foundation

/// Browsers yt-dlp can borrow a YouTube session from
/// (`--cookies-from-browser`). Off by default, and chosen by the person:
/// the session is theirs, and so is the decision.
///
/// Three things come with it, and the interface says them before they
/// happen, not after:
/// - Safari keeps its cookies in a folder macOS protects. Reading it needs
///   Full Disk Access, granted to TBD (yt-dlp runs as TBD's child, so the
///   permission is TBD's to ask for).
/// - Chrome and the browsers built on it encrypt their cookies with a key in
///   the login keychain. macOS asks for the password, in the name of
///   `yt-dlp`, the first time.
/// - yt-dlp's own advice: use an account you can afford to lose. Reusing an
///   active session can rotate its tokens and sign the browser out.
enum CookieBrowser: String, CaseIterable, Identifiable, Sendable, Codable {
    case safari, chrome, firefox, brave, edge, chromium, opera, vivaldi

    var id: String { rawValue }

    /// The name yt-dlp expects after `--cookies-from-browser`.
    var ytDlpName: String { rawValue }

    var label: String {
        switch self {
        case .safari:   return "Safari"
        case .chrome:   return "Google Chrome"
        case .firefox:  return "Firefox"
        case .brave:    return "Brave"
        case .edge:     return "Microsoft Edge"
        case .chromium: return "Chromium"
        case .opera:    return "Opera"
        case .vivaldi:  return "Vivaldi"
        }
    }

    /// Bundle identifiers that mean "this browser is installed".
    var bundleIdentifiers: [String] {
        switch self {
        case .safari:   return ["com.apple.Safari"]
        case .chrome:   return ["com.google.Chrome"]
        case .firefox:  return ["org.mozilla.firefox"]
        case .brave:    return ["com.brave.Browser"]
        case .edge:     return ["com.microsoft.edgemac"]
        case .chromium: return ["org.chromium.Chromium"]
        case .opera:    return ["com.operasoftware.Opera"]
        case .vivaldi:  return ["com.vivaldi.Vivaldi"]
        }
    }

    /// Cookies encrypted with a key from the login keychain: macOS asks for
    /// the password the first time yt-dlp reads them.
    var usesKeychain: Bool {
        switch self {
        case .safari, .firefox: return false
        default: return true
        }
    }

    /// Name of the keychain item macOS will mention in its prompt.
    var keychainItem: String? {
        switch self {
        case .chrome:   return "Chrome Safe Storage"
        case .brave:    return "Brave Safe Storage"
        case .edge:     return "Microsoft Edge Safe Storage"
        case .chromium: return "Chromium Safe Storage"
        case .opera:    return "Opera Safe Storage"
        case .vivaldi:  return "Vivaldi Safe Storage"
        case .safari, .firefox: return nil
        }
    }

    var needsFullDiskAccess: Bool { self == .safari }

    /// The browsers installed on this Mac, in the order above.
    static func installed(isInstalled: (String) -> Bool) -> [CookieBrowser] {
        allCases.filter { $0.bundleIdentifiers.contains(where: isInstalled) }
    }

    /// Arguments for yt-dlp; nothing when the option is off.
    static func arguments(for browser: CookieBrowser?) -> [String] {
        browser.map { ["--cookies-from-browser", $0.ytDlpName] } ?? []
    }

    // MARK: - Safari and Full Disk Access

    /// Where Safari keeps its cookies (sandboxed Safari, macOS 10.14+).
    static var safariCookiesFile: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies")
    }

    /// Can this process read Safari's cookies? Opening the file is the test:
    /// without Full Disk Access it fails with "Operation not permitted", and
    /// macOS shows no prompt for it.
    static func canReadSafariCookies() -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: safariCookiesFile) else { return false }
        try? handle.close()
        return true
    }

    /// Opens System Settings at Full Disk Access.
    static let fullDiskAccessSettings = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!

    // MARK: - Errors

    /// Turns yt-dlp's cookie failures into a sentence that says what to do.
    /// Without this, a missing permission reads as a download that failed
    /// for no reason. Returns `nil` when the message is about something else.
    static func explain(_ message: String) -> String? {
        let lower = message.lowercased()
        let aboutCookies = lower.contains("cookie") || lower.contains("safe storage")
            || lower.contains("keychain")
        guard aboutCookies else { return nil }

        if lower.contains("binarycookies") || lower.contains("operation not permitted") {
            return "TBD can't read Safari's cookies. Give TBD Full Disk Access in "
                + "System Settings > Privacy & Security, or turn off browser cookies in Settings."
        }
        if lower.contains("safe storage") || lower.contains("keychain")
            || lower.contains("decrypt") {
            return "TBD can't read the browser's cookies: the keychain password was not given. "
                + "Try again and choose Allow, or turn off browser cookies in Settings."
        }
        if lower.contains("could not find") || lower.contains("no such file")
            || lower.contains("not find") {
            return "TBD found no cookies for this browser. Open it once and sign in to YouTube, "
                + "or choose another browser in Settings."
        }
        return nil
    }
}
