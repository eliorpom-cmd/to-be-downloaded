import AppKit

extension Notification.Name {
    /// Lien reçu de l'extérieur : schéma `downloader://`, service macOS,
    /// extension de partage.
    static let externalDownloadRequest = Notification.Name("externalDownloadRequest")
}

/// Réception des liens venus d'ailleurs que de la fenêtre.
///
/// Passe par un délégué d'application et non par `.onOpenURL` : ce dernier
/// n'est délivré qu'à une scène affichée, alors que l'app peut très bien
/// tourner sans fenêtre ouverte, réduite à son icône de barre des menus.
final class AppDelegate: NSObject, NSApplicationDelegate {

    private let services = ServiceProvider()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = services
        // Sans cela, l'entrée n'apparaît dans le menu Services qu'après un
        // redémarrage de session.
        NSUpdateDynamicServices()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { Self.handle(url) }
    }

    /// `downloader://download?url=<lien encodé>`
    static func handle(_ url: URL) {
        guard url.scheme?.lowercased() == "downloader",
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

/// Entrée « Download with … » du menu Services, disponible dès qu'un lien
/// YouTube est sélectionné dans n'importe quelle app.
///
/// C'est le complément de l'extension de partage : un service est fourni par
/// l'app elle-même, donc il fonctionne quoi qu'il arrive, là où une extension
/// est un bundle distinct que le système peut refuser de charger.
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
