import Foundation
import CoreGraphics
import AppKit
import SwiftUI

/// Rend l'icône de l'app en PNG, servie à la PWA et à `apple-touch-icon`.
///
/// Même dessin que l'icône du bundle : la pastille claire aux proportions macOS
/// et le tracé exact du logo (`MascotShape`). L'icône sur l'écran d'accueil d'un
/// téléphone est donc la même que celle du Dock.
enum AppIcon {

    /// Icône d'écran d'accueil : mêmes proportions que celle du Dock.
    static func png(size: Int) -> Data? {
        render(size: size, marginRatio: 100.0 / 1024.0, logoRatio: 0.58)
    }

    /// Icône d'onglet. La marge et le rapport du Dock sont calculés pour une
    /// icône de 128 px ; à 16 px dans un onglet, ils réduisent le logo à un
    /// point. On colle donc la pastille au bord et on grossit le tracé.
    static func favicon(size: Int) -> Data? {
        render(size: size, marginRatio: 0, logoRatio: 0.74)
    }

    private static func render(size: Int, marginRatio: CGFloat, logoRatio: CGFloat) -> Data? {
        let s = CGFloat(size)
        guard let ctx = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Pastille : proportions des icônes macOS (rayon 185/1024).
        let margin = s * marginRatio
        let body = CGRect(x: margin, y: margin, width: s - 2 * margin, height: s - 2 * margin)
        let radius = body.width * 185.0 / 824.0
        ctx.addPath(CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.setFillColor(CGColor(red: 0.98, green: 0.98, blue: 0.98, alpha: 1))
        ctx.fillPath()

        let target = body.width * logoRatio
        let height = target * 920.0 / 930.0
        let logoRect = CGRect(x: body.midX - target / 2,
                              y: body.midY - height / 2,
                              width: target, height: height)

        // Le tracé est exprimé en coordonnées SwiftUI (y vers le bas) alors que
        // CoreGraphics compte depuis le bas : sans ce retournement, la mascotte
        // sort sur la tête.
        ctx.saveGState()
        ctx.translateBy(x: 0, y: s)
        ctx.scaleBy(x: 1, y: -1)
        let flipped = CGRect(x: logoRect.minX, y: s - logoRect.maxY,
                             width: logoRect.width, height: logoRect.height)
        ctx.addPath(MascotShape().path(in: flipped).cgPath)
        ctx.setFillColor(CGColor(red: 0.04, green: 0.04, blue: 0.04, alpha: 1))
        ctx.fillPath(using: .winding)
        ctx.restoreGState()

        guard let cgImage = ctx.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
    }
}
