//
//  Fabrique App/Resources/AppIcon.icns à partir du logo.
//
//  On dessine le TRACÉ VECTORIEL (`MascotShape`, la vectorisation exacte de
//  image.png) et non le PNG : le PNG a un fond blanc opaque, qui poserait un
//  carré blanc au milieu de la pastille. Le tracé, lui, laisse l'œil et la
//  flèche en négatif, comme sur le dessin d'origine.
//
//  La pastille reprend les proportions macOS depuis Big Sur : marge de 100/1024,
//  rayon de 185/1024.
//
//  Usage :  ./scripts/make-icon.sh
//
import AppKit
import SwiftUI
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let outputDirectory = root.appendingPathComponent("App/Resources")
let iconset = FileManager.default.temporaryDirectory
    .appendingPathComponent("AppIcon-\(UUID().uuidString).iconset")

/// Dessine l'icône complète à la taille demandée.
func renderIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
        guard let context = NSGraphicsContext.current?.cgContext else { return false }

        // Pastille : proportions officielles des icônes macOS.
        let margin = size * 100.0 / 1024.0
        let body = rect.insetBy(dx: margin, dy: margin)
        let radius = size * 185.0 / 1024.0
        let squircle = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)

        context.saveGState()
        squircle.addClip()
        // Dégradé très léger : à plat, l'icône paraît terne dans le Dock.
        let gradient = NSGradient(colors: [
            NSColor(calibratedWhite: 1.0, alpha: 1),
            NSColor(calibratedWhite: 0.925, alpha: 1),
        ])
        gradient?.draw(in: body, angle: -90)
        context.restoreGState()

        // Liseré discret, sinon la pastille blanche se fond dans un Dock clair.
        NSColor(calibratedWhite: 0, alpha: 0.10).setStroke()
        squircle.lineWidth = max(1, size / 512)
        squircle.stroke()

        // Logo centré, à 58 % de la pastille. Ratio d'origine 930×920.
        let target = body.width * 0.58
        let logoRect = NSRect(
            x: body.midX - target / 2,
            y: body.midY - (target * 920.0 / 930.0) / 2,
            width: target,
            height: target * 920.0 / 930.0)

        context.saveGState()
        // Le tracé est en coordonnées SwiftUI (y vers le bas) : on retourne le
        // repère, sinon la mascotte sort sur la tête.
        context.translateBy(x: 0, y: rect.height)
        context.scaleBy(x: 1, y: -1)
        let flipped = NSRect(x: logoRect.minX,
                             y: rect.height - logoRect.maxY,
                             width: logoRect.width,
                             height: logoRect.height)
        context.addPath(MascotShape().path(in: flipped).cgPath)
        context.setFillColor(NSColor(calibratedWhite: 0.04, alpha: 1).cgColor)
        context.fillPath(using: .winding)
        context.restoreGState()

        return true
    }
    return image
}

func writePNG(_ image: NSImage, to url: URL) throws {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let data = rep.representation(using: .png, properties: [:])
    else { throw NSError(domain: "icon", code: 1) }
    try data.write(to: url)
}

try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

// Tailles exigées par iconutil.
let variants: [(name: String, pixels: CGFloat)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]

for variant in variants {
    try writePNG(renderIcon(size: variant.pixels), to: iconset.appendingPathComponent(variant.name))
}

let icns = outputDirectory.appendingPathComponent("AppIcon.icns")
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try process.run()
process.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)

guard process.terminationStatus == 0 else {
    FileHandle.standardError.write(Data("❌ iconutil a échoué\n".utf8))
    exit(1)
}
print("✅ \(icns.path)")

// Aperçu à taille réelle, pratique pour juger le rendu.
let preview = outputDirectory.appendingPathComponent("AppIcon-preview.png")
try writePNG(renderIcon(size: 512), to: preview)
print("   aperçu : \(preview.path)")
