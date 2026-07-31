// TBD — To be downloaded. Copyright (C) 2026 Elior Pommier.
// Licensed under the GNU AGPL v3 or later. See LICENSE and NOTICE.
import Cocoa
import UniformTypeIdentifiers

/// Share extension: "Download with …" in Safari's Share menu and any app that
/// shares a URL.
///
/// No interface. A share extension normally opens a composition window; here there
/// is nothing to compose — we grab the link, pass it to the app via its URL scheme,
/// and close. The extension does not download anything itself: it has no binaries,
/// no queue, no library.
final class ShareViewController: NSViewController {

    override func loadView() {
        view = NSView(frame: .zero)
        extractLink()
    }

    private func extractLink() {
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let attachments = item.attachments, !attachments.isEmpty
        else { return finish() }

        // A URL first; failing that, text, because Safari sometimes shares the
        // selection rather than the page address.
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

        // Only the app verifies that the link is acceptable.
        extensionContext?.open(deepLink) { [weak self] _ in
            DispatchQueue.main.async { self?.finish() }
        }
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }
}
