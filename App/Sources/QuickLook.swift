// TBD — To be downloaded. Copyright (C) 2026 Elior Pommier.
// Licensed under the GNU AGPL v3 or later. See LICENSE and NOTICE.
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
///
/// Hence the isolation being placed member by member: everything that touches
/// `QLPreviewPanel` is `@MainActor`, since AppKit is, and only the two data
/// source methods stay nonisolated — which is exactly what the protocol
/// requires and what the panel calls, on the main thread, between them.
final class QuickLook: NSObject, @unchecked Sendable {
    @MainActor static let shared = QuickLook()

    private var urls: [URL] = []

    /// Open the preview, or close it if it's already showing this file — that's
    /// the spacebar behavior in Finder.
    @MainActor
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

    @MainActor
    var isVisible: Bool { QLPreviewPanel.shared()?.isVisible ?? false }
}

extension QuickLook: QLPreviewPanelDataSource {
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { urls.count }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        urls[index] as NSURL
    }
}
