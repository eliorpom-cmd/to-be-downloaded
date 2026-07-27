import AppKit
import Quartz

/// Aperçu Quick Look, déclenché par la barre d'espace comme dans le Finder.
///
/// SwiftUI n'expose rien pour cela : on pilote directement le panneau partagé.
/// Comme aucune autre vue de l'app ne revendique le contrôle du panneau, lui
/// fournir la source de données sans passer par la chaîne des répondeurs suffit.
/// Pas de `@MainActor` sur la classe : `QLPreviewPanelDataSource` est un
/// protocole Objective-C non isolé, et le conformer depuis un type isolé
/// traverse la frontière d'acteur. Le panneau n'appelle sa source que depuis le
/// fil principal, où tout le reste de la classe est appelé aussi.
final class QuickLook: NSObject, @unchecked Sendable {
    @MainActor static let shared = QuickLook()

    private var urls: [URL] = []

    /// Ouvre l'aperçu, ou le referme s'il montre déjà ce fichier — c'est le
    /// comportement de la barre d'espace dans le Finder.
    func toggle(_ url: URL) {
        guard let panel = QLPreviewPanel.shared() else { return }
        if panel.isVisible, urls.first == url {
            panel.orderOut(nil)
            return
        }
        urls = [url]
        panel.dataSource = self
        panel.makeKeyAndOrderFront(nil)
        panel.reloadData()
    }

    var isVisible: Bool { QLPreviewPanel.shared()?.isVisible ?? false }
}

extension QuickLook: QLPreviewPanelDataSource {
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { urls.count }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        urls[index] as NSURL
    }
}
