import Foundation
import CoreGraphics
import AppKit
import SwiftUI

/// Renders the app icon as PNG, served to the PWA and `apple-touch-icon`.
///
/// Same drawing as the bundle icon: the tile with the mascot hollowed out
/// (`AppIconShape`, path from `App/Resources/AppIcon.icon`). The icon on a
/// phone's home screen is thus the same as the Dock icon.
///
/// Always in light variant: nothing here says which theme the icon will be
/// displayed in, and light is what macOS shows by default.
enum AppIcon {

    /// Icon background and tile ink: `Theme.canvas` and `Theme.ink` in light,
    /// frozen — a PNG does not follow the theme.
    private static let paper = CGColor(red: 0.98, green: 0.98, blue: 0.98, alpha: 1)
    private static let ink = CGColor(red: 0.04, green: 0.04, blue: 0.04, alpha: 1)

    /// Home screen icon: the tile and its margin, like in the Dock (80/1024,
    /// the margin of the original SVG). iOS rounds the square itself.
    static func png(size: Int) -> Data? {
        render(size: size, marginRatio: 80.0 / 1024.0)
    }

    /// Tab icon. The Dock's margin is calculated for a 128 px icon; at 16 px it
    /// would reduce the tile to a dot. So we stick it to the edges: only the four
    /// background corners remain.
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

        // The path is expressed in SwiftUI coordinates (y down) while CoreGraphics
        // counts from the bottom: without this flip, the mascot comes out upside down.
        ctx.translateBy(x: 0, y: s)
        ctx.scaleBy(x: 1, y: -1)

        let margin = s * marginRatio
        let body = CGRect(x: margin, y: margin, width: s - 2 * margin, height: s - 2 * margin)
        ctx.addPath(AppIconShape().path(in: body).cgPath)
        ctx.setFillColor(ink)
        // Non-zero: the arrow and eyes are sub-paths with reverse winding, so
        // holes. In even-odd the tile would become a solid square.
        ctx.fillPath(using: .winding)

        guard let cgImage = ctx.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
    }
}
