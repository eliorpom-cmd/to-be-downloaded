import AppKit

/// Progression dessinée sur l'icône du Dock.
///
/// Le badge à lui seul dit « il se passe quelque chose » mais pas « où ça en
/// est ». La barre, elle, se lit d'un coup d'œil depuis une autre app — c'est
/// tout l'intérêt d'avoir une icône dans le Dock.
@MainActor
enum DockProgress {

    private static let tileView = DockTileView()
    /// Dernier centième dessiné : la progression arrive plusieurs fois par
    /// seconde, redessiner l'icône à chaque ligne ne changerait rien à l'œil.
    private static var lastDrawn: Int?

    /// `fraction` à `nil` remet l'icône normale.
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

/// Icône de l'app surmontée d'une barre de progression.
private final class DockTileView: NSView {
    var fraction: Double = 0

    override func draw(_ dirtyRect: NSRect) {
        // L'icône d'abord : remplacer la `contentView` du Dock la retire, il
        // faut donc la redessiner soi-même.
        NSApp.applicationIconImage?.draw(
            in: bounds, from: .zero, operation: .sourceOver, fraction: 1)

        let height = bounds.height * 0.09
        let inset = bounds.width * 0.12
        let track = NSRect(x: inset, y: bounds.height * 0.06,
                           width: bounds.width - inset * 2, height: height)
        let radius = height / 2

        // Piste sombre translucide : lisible sur une icône claire comme sombre.
        NSColor(white: 0, alpha: 0.55).setFill()
        NSBezierPath(roundedRect: track, xRadius: radius, yRadius: radius).fill()

        guard fraction > 0 else { return }
        var filled = track
        // Jamais moins large que haute, sinon la pastille arrondie se déforme.
        filled.size.width = max(height, track.width * CGFloat(fraction))
        NSColor.white.setFill()
        NSBezierPath(roundedRect: filled, xRadius: radius, yRadius: radius).fill()
    }
}
