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

    static func png(size: Int) -> Data? {
        let s = CGFloat(size)
        guard let ctx = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Pastille : proportions des icônes macOS (marge 100/1024, rayon 185/1024).
        let margin = s * 100.0 / 1024.0
        let body = CGRect(x: margin, y: margin, width: s - 2 * margin, height: s - 2 * margin)
        let radius = s * 185.0 / 1024.0
        ctx.addPath(CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.setFillColor(CGColor(red: 0.98, green: 0.98, blue: 0.98, alpha: 1))
        ctx.fillPath()

        // Logo centré, à 58 % de la pastille.
        let target = body.width * 0.58
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
