import Cocoa
import UniformTypeIdentifiers

/// Extension de partage : « Download with … » dans le menu Partager de Safari
/// et de toute app qui partage une URL.
///
/// Sans interface. Une extension de partage ouvre normalement une fenêtre de
/// rédaction ; ici il n'y a rien à rédiger — on récupère le lien, on le passe à
/// l'app par son schéma d'URL, et on referme. L'extension ne télécharge rien
/// elle-même : elle n'a ni les binaires, ni la file d'attente, ni la
/// bibliothèque.
final class ShareViewController: NSViewController {

    override func loadView() {
        view = NSView(frame: .zero)
        extractLink()
    }

    private func extractLink() {
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let attachments = item.attachments, !attachments.isEmpty
        else { return finish() }

        // Une URL d'abord ; à défaut du texte, car Safari partage parfois la
        // sélection plutôt que l'adresse de la page.
        let identifiers = [UTType.url.identifier, UTType.plainText.identifier]
        for identifier in identifiers {
            guard let provider = attachments.first(where: {
                $0.hasItemConformingToTypeIdentifier(identifier)
            }) else { continue }

            provider.loadItem(forTypeIdentifier: identifier) { [weak self] value, _ in
                let link = (value as? URL)?.absoluteString
                    ?? (value as? String)
                    ?? (value as? Data).flatMap { String(data: $0, encoding: .utf8) }
                DispatchQueue.main.async { self?.hand(over: link) }
            }
            return
        }
        finish()
    }

    private func hand(over link: String?) {
        guard let link = link?.trimmingCharacters(in: .whitespacesAndNewlines),
              !link.isEmpty,
              var components = URLComponents(string: "\(AppConfig.urlScheme)://download")
        else { return finish() }

        components.queryItems = [URLQueryItem(name: "url", value: link)]
        guard let deepLink = components.url else { return finish() }

        // C'est l'app, et elle seule, qui vérifie que le lien est acceptable.
        extensionContext?.open(deepLink) { [weak self] _ in
            DispatchQueue.main.async { self?.finish() }
        }
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }
}
