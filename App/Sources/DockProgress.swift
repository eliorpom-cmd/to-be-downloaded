import AppKit

/// Progress drawn on the Dock icon.
///
/// The badge alone says "something's happening" but not "how far along".
/// The bar reads at a glance from another app — that's the whole point of
/// having an icon in the Dock.
@MainActor
enum DockProgress {

    private static let tileView = DockTileView()
    /// Last hundredth drawn: progress arrives many times a second, redrawing
    /// the icon every frame would make no visible difference.
    private static var lastDrawn: Int?

    /// Pass `fraction` as `nil` to restore the normal icon.
    static func update(fraction: Double?, badge: Int) {
        let tile = NSApp.dockTile
        tile.badgeLabel = badge > 0 ? "\(badge)" : nil

        let step = fraction.map { Int(($0 * 100).rounded()) }
        guard step != lastDrawn else { return }
        lastDrawn = step

        guard let fraction else {
            if tile.contentView != nil {
                tile.contentView = nil
                tile.display()
            }
            return
        }

        tileView.fraction = max(0, min(1, fraction))
        if tile.contentView !== tileView { tile.contentView = tileView }
        tile.display()
    }
}

/// App icon topped with a progress bar.
private final class DockTileView: NSView {
    var fraction: Double = 0

    override func draw(_ dirtyRect: NSRect) {
        // Draw the icon first: replacing the Dock's `contentView` removes it,
        // so we must redraw it ourselves.
        NSApp.applicationIconImage?.draw(
            in: bounds, from: .zero, operation: .sourceOver, fraction: 1)

        let height = bounds.height * 0.09
        let inset = bounds.width * 0.12
        let track = NSRect(x: inset, y: bounds.height * 0.06,
                           width: bounds.width - inset * 2, height: height)
        let radius = height / 2

        // Dark translucent track: readable on both light and dark icons.
        NSColor(white: 0, alpha: 0.55).setFill()
        NSBezierPath(roundedRect: track, xRadius: radius, yRadius: radius).fill()

        guard fraction > 0 else { return }
        var filled = track
        // Never narrower than tall, else the rounded pill deforms.
        filled.size.width = max(height, track.width * CGFloat(fraction))
        NSColor.white.setFill()
        NSBezierPath(roundedRect: filled, xRadius: radius, yRadius: radius).fill()
    }
}
