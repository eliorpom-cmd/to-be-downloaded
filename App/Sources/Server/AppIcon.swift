// TBD — To Be Downloaded. Copyright (C) 2026 Elior Pommier.
// Licensed under the GNU AGPL v3 or later. See LICENSE and NOTICE.
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
    /// the margin of the original SVG). iOS rounds the square itself, and
    /// wants an opaque square to round — a transparent PWA icon gets
    /// composited onto whatever the system feels like.
    static func png(size: Int) -> Data? {
        render(size: size, marginRatio: 80.0 / 1024.0, opaqueBackground: true)
    }

    /// Tab icon. The Dock's margin is calculated for a 128 px icon; at 16 px it
    /// would reduce the tile to a dot, so the tile goes edge to edge.
    ///
    /// **No background.** A browser tab is not a canvas we own, and an opaque
    /// square sitting in it read as a sticker rather than an icon. What is
    /// left is the ink tile with the mascot cut clean through it — the same
    /// rendering as the SVG logo on the page itself.
    ///
    /// Filling the face instead was tried and abandoned. The mark is not a
    /// closed shape: the arrow's stem runs to the top edge of the tile, so
    /// the face is open to the outside, while the two eyes are enclosed.
    /// Anything that paints the holes reaches the eyes and not the arrow, and
    /// a half-opaque half-transparent face is worse than either.
    static func favicon(size: Int) -> Data? {
        render(size: size, marginRatio: 0, opaqueBackground: false)
    }

    private static func render(size: Int, marginRatio: CGFloat,
                               opaqueBackground: Bool) -> Data? {
        let s = CGFloat(size)
        guard let ctx = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        if opaqueBackground {
            ctx.setFillColor(paper)
            ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
        }

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
