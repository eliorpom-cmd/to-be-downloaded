import Foundation
import CoreGraphics
import AppKit
import SwiftUI

/// Rend l'icône de l'app en PNG, servie à la PWA et à `apple-touch-icon`.
///
/// Même dessin que l'icône du bundle : la pastille dont la mascotte est évidée
/// (`AppIconShape`, tracé issu de `App/Resources/AppIcon.icon`). L'icône sur
/// l'écran d'accueil d'un téléphone est donc la même que celle du Dock.
///
/// Toujours en variante claire : rien ici ne dit dans quel thème l'icône sera
/// affichée, et le clair est celui que macOS montre par défaut.
enum AppIcon {

    /// Fond de l'icône, et l'encre de la pastille : `Theme.canvas` et
    /// `Theme.ink` en clair, figés — un PNG ne suit pas le thème.
    private static let paper = CGColor(red: 0.98, green: 0.98, blue: 0.98, alpha: 1)
    private static let ink = CGColor(red: 0.04, green: 0.04, blue: 0.04, alpha: 1)

    /// Icône d'écran d'accueil : la pastille et sa marge, comme dans le Dock
    /// (80/1024, la marge du SVG d'origine). iOS arrondit lui-même le carré.
    static func png(size: Int) -> Data? {
        render(size: size, marginRatio: 80.0 / 1024.0)
    }

    /// Icône d'onglet. La marge du Dock est calculée pour une icône de 128 px ;
    /// à 16 px elle réduirait la pastille à un point. On la colle donc aux
    /// bords : ne restent que les quatre coins de fond.
    static func favicon(size: Int) -> Data? {
        render(size: size, marginRatio: 0)
    }

    private static func render(size: Int, marginRatio: CGFloat) -> Data? {
        let s = CGFloat(size)
        guard let ctx = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.setFillColor(paper)
        ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))

        // Le tracé est exprimé en coordonnées SwiftUI (y vers le bas) alors que
        // CoreGraphics compte depuis le bas : sans ce retournement, la mascotte
        // sort sur la tête.
        ctx.translateBy(x: 0, y: s)
        ctx.scaleBy(x: 1, y: -1)

        let margin = s * marginRatio
        let body = CGRect(x: margin, y: margin, width: s - 2 * margin, height: s - 2 * margin)
        ctx.addPath(AppIconShape().path(in: body).cgPath)
        ctx.setFillColor(ink)
        // Non-zero : la flèche et les yeux sont des sous-tracés d'orientation
        // inverse, donc des trous. En even-odd la pastille devient un carré plein.
        ctx.fillPath(using: .winding)

        guard let cgImage = ctx.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
    }
}
