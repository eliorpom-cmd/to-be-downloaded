import AppKit
import Quartz

/// Quick Look preview, triggered by spacebar like in Finder.
///
/// SwiftUI exposes nothing for this: drive the shared panel directly. Since no
/// other view claims control of the panel, giving it a data source without
/// going through the responder chain suffices. No `@MainActor` on the class:
/// `QLPreviewPanelDataSource` is an unisolated Objective-C protocol, and
/// conforming from an isolated type crosses the actor boundary. The panel only
/// calls its source from the main thread, where the rest of the class is called too.
final class QuickLook: NSObject, @unchecked Sendable {
    @MainActor static let shared = QuickLook()

    private var urls: [URL] = []

    /// Open the preview, or close it if it's already showing this file — that's
    /// the spacebar behavior in Finder.
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
