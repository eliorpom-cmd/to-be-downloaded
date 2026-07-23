import Foundation
import CoreGraphics
import AppKit

/// Rend l'icône de l'app en PNG (monochrome, sur-marque) : carré arrondi noir
/// + flèche de téléchargement blanche. Dessin via CoreGraphics (thread-safe,
/// pas de contexte AppKit à verrouiller), servi à la PWA et à apple-touch-icon.
enum AppIcon {
    static func png(size: Int) -> Data? {
        let s = CGFloat(size)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Fond : carré arrondi quasi-noir.
        let inset = s * 0.06
        let rect = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
        let corner = s * 0.225      // squircle façon iOS/macOS
        let bg = CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)
        ctx.addPath(bg)
        ctx.setFillColor(CGColor(red: 0.04, green: 0.04, blue: 0.04, alpha: 1))
        ctx.fillPath()

        // Flèche de téléchargement blanche (repère y bas-gauche en CoreGraphics).
        ctx.setFillColor(CGColor(red: 0.96, green: 0.96, blue: 0.96, alpha: 1))
        let cx = s / 2
        let stemW = s * 0.10
        let stemTop = s * 0.72
        let stemBottom = s * 0.40
        // Hampe
        ctx.fill(CGRect(x: cx - stemW / 2, y: stemBottom, width: stemW, height: stemTop - stemBottom))
        // Pointe (triangle)
        let head = s * 0.20
        ctx.move(to: CGPoint(x: cx - head, y: stemBottom + head * 0.2))
        ctx.addLine(to: CGPoint(x: cx + head, y: stemBottom + head * 0.2))
        ctx.addLine(to: CGPoint(x: cx, y: s * 0.28))
        ctx.closePath()
        ctx.fillPath()
        // Socle (barre sous la flèche)
        let baseW = s * 0.40
        ctx.fill(CGRect(x: cx - baseW / 2, y: s * 0.24, width: baseW, height: s * 0.055))

        guard let cgImage = ctx.makeImage() else { return nil }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        return rep.representation(using: .png, properties: [:])
    }
}
