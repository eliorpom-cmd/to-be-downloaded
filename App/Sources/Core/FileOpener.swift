// TBD — To be downloaded. Copyright (C) 2026 Elior Pommier.
// Licensed under the GNU AGPL v3 or later. See LICENSE and NOTICE.
import AppKit

/// Opening produced files.
enum FileOpener {

    /// Launch the file in the default player, and if that fails, show it in
    /// the Finder.
    ///
    /// `NSWorkspace.open` fails silently when the associated application
    /// refuses to start (freshly installed and still quarantined, for example):
    /// macOS then displays "Item could not be opened" and the user is left with
    /// nothing. Revealing the file at least leaves a way out.
    ///
    /// See `NSWorkspace.open(_:)`.
    static func play(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            reveal(url)
            return
        }
        if !NSWorkspace.shared.open(url) {
            reveal(url)
        }
    }

    static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
