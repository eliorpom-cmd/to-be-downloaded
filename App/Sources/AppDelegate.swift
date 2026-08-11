// TBD — To be downloaded. Copyright (C) 2026 Elior Pommier.
// Licensed under the GNU AGPL v3 or later. See LICENSE and NOTICE.
import AppKit

extension Notification.Name {
    /// Link received from outside: `tbd://` scheme, macOS service,
    /// share extension.
    static let externalDownloadRequest = Notification.Name("externalDownloadRequest")
}

/// Receiving links from outside the window.
///
/// Goes through an application delegate rather than `.onOpenURL`: the latter
/// is only delivered to a displayed scene, whereas the app can run fine with
/// no window open, reduced to its menu bar icon.
final class AppDelegate: NSObject, NSApplicationDelegate {

    private let services = ServiceProvider()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Belt to the removed "New Window" menu item: macOS can still merge
        // windows into tabs on its own (the ⌘N-free path — window menu, or a
        // system preference set to "always"). One window, one queue, no tab bar.
        NSWindow.allowsAutomaticWindowTabbing = false
        NSApp.servicesProvider = services
        // Without this, the entry won't appear in the Services menu until
        // the session is restarted.
        NSUpdateDynamicServices()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { Self.handle(url) }
    }

    /// `tbd://download?url=<encoded link>`
    static func handle(_ url: URL) {
        guard url.scheme?.lowercased() == AppConfig.urlScheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let link = components.queryItems?.first(where: { $0.name == "url" })?.value,
              YouTubeLink.isValid(link)
        else { return }
        post(link)
    }

    static func post(_ link: String) {
        NotificationCenter.default.post(
            name: .externalDownloadRequest, object: nil, userInfo: ["url": link])
    }
}

/// "Download with …" entry in the Services menu, available as soon as a
/// YouTube link is selected in any app.
///
/// This complements the share extension: a service is provided by
/// the app itself, so it works no matter what, whereas an extension
/// is a separate bundle that the system might refuse to load.
final class ServiceProvider: NSObject {
    @objc func downloadYouTubeLink(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString>
    ) {
        let candidates = [
            pasteboard.string(forType: .URL),
            pasteboard.string(forType: .string),
        ].compactMap { $0 }

        guard let link = candidates
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: YouTubeLink.isValid)
        else {
            error.pointee = "That is not a YouTube link." as NSString
            return
        }
        AppDelegate.post(link)
    }
}
