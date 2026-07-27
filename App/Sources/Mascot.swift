import SwiftUI

/// Mascotte de l'app — tracé vectoriel EXACT du dessin d'Elior (`image.png`),
/// obtenu par vectorisation (potrace) puis converti en `Path` SwiftUI. On NE
/// redessine rien : la silhouette est celle du dessin d'origine, au pixel près.
///
/// Monochrome : la silhouette est peinte en `Theme.ink`, l'œil (trou du tracé)
/// et la bouche-flèche laissent voir le fond.
///
/// Volontairement IMMOBILE : le balancement permanent attirait l'œil sans rien
/// dire. `isActive` est conservé pour les appelants, mais n'anime plus rien.
struct MascotView: View {
    var size: CGFloat = 44
    var isActive: Bool = false

    // Ratio exact de l'image source (930×920) pour ne pas déformer.
    private var height: CGFloat { size * 920.0 / 930.0 }

    var body: some View {
        MascotShape()
            .fill(Theme.ink)
            .frame(width: size, height: height)
    }
}

/// Rendu AppKit de la mascotte, pour les endroits qui exigent une `NSImage` :
/// barre des menus, icône d'app, notifications.
enum MascotImage {

    /// Données de tracé SVG (`d="…"`) du logo, dans un carré `viewBox` 100×100.
    ///
    /// Généré depuis le MÊME `MascotShape` que l'app : le logo n'existe qu'à un
    /// seul endroit. Sur la page web il est peint en `currentColor`, donc il
    /// s'inverse tout seul en thème sombre — contrairement à un PNG.
    static func svgPathData(viewBox: CGFloat = 100) -> String {
        let rect = CGRect(x: 0, y: 0, width: viewBox, height: viewBox * 920.0 / 930.0)
        var commands: [String] = []
        func n(_ value: CGFloat) -> String { String(format: "%.2f", value) }

        MascotShape().path(in: rect).cgPath.applyWithBlock { element in
            let points = element.pointee.points
            switch element.pointee.type {
            case .moveToPoint:
                commands.append("M\(n(points[0].x)) \(n(points[0].y))")
            case .addLineToPoint:
                commands.append("L\(n(points[0].x)) \(n(points[0].y))")
            case .addQuadCurveToPoint:
                commands.append("Q\(n(points[0].x)) \(n(points[0].y)) \(n(points[1].x)) \(n(points[1].y))")
            case .addCurveToPoint:
                commands.append("C\(n(points[0].x)) \(n(points[0].y)) "
                                + "\(n(points[1].x)) \(n(points[1].y)) "
                                + "\(n(points[2].x)) \(n(points[2].y))")
            case .closeSubpath:
                commands.append("Z")
            @unknown default:
                break
            }
        }
        return commands.joined(separator: " ")
    }

    /// Glyphe de barre des menus : le tracé ORIGINAL du logo, sans redessin.
    ///
    /// Rendu dans un bitmap HORS ÉCRAN plutôt que via
    /// `NSImage(size:flipped:drawingHandler:)` : ce dernier peint directement
    /// dans le contexte de destination, où l'on ne maîtrise ni le suréchantil-
    /// lonnage ni les modes de fusion. Ici on choisit l'échelle (3×) pour que
    /// l'œil et l'encoche de la flèche survivent à la réduction.
    ///
    /// Image *template* : macOS la recolore selon le thème de la barre des
    /// menus (clair, sombre, inversion au clic).
    static func menuBar(size: CGFloat = 18) -> NSImage {
        let scale: CGFloat = 3
        let pixels = Int((size * scale).rounded())
        guard let context = CGContext(
            data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return NSImage(size: NSSize(width: size, height: size)) }

        context.scaleBy(x: scale, y: scale)
        // Repère y vers le bas, pour raisonner comme dans le reste de l'UI.
        context.translateBy(x: 0, y: size)
        context.scaleBy(x: 1, y: -1)
        context.setShouldAntialias(true)

        // Ratio d'origine 930×920, centré verticalement dans le carré.
        let height = size * 920.0 / 930.0
        let rect = CGRect(x: 0, y: (size - height) / 2, width: size, height: height)

        context.addPath(MascotShape().path(in: rect).cgPath)
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        // Non-zero : l'œil et la flèche sont des sous-tracés inverses, donc des
        // trous — c'est ce qui rend le logo lisible plutôt qu'un disque plein.
        context.fillPath(using: .winding)

        guard let cgImage = context.makeImage() else {
            return NSImage(size: NSSize(width: size, height: size))
        }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: size, height: size))
        image.isTemplate = true
        return image
    }
}

/// Silhouette exacte de `image.png` (vectorisée). Coordonnées normalisées 0…1,
/// remises à l'échelle du `rect` fourni. Rempli en non-zero : l'œil (sous-tracé
/// d'orientation inverse) reste bien un trou.
struct MascotShape: Shape {
    func path(in rect: CGRect) -> Path {
        func p(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        var path = Path()
        path.move(to: p(0.4731, 0.0104))
        path.addCurve(to: p(0.1863, 0.1279), control1: p(0.3628, 0.0187), control2: p(0.2680, 0.0575))
        path.addCurve(to: p(0.1072, 0.2154), control1: p(0.1599, 0.1508), control2: p(0.1280, 0.1861))
        path.addCurve(to: p(0.0575, 0.6934), control1: p(0.0095, 0.3539), control2: p(-0.0095, 0.5360))
        path.addCurve(to: p(0.1047, 0.7787), control1: p(0.0686, 0.7196), control2: p(0.0880, 0.7546))
        path.addCurve(to: p(0.2242, 0.8997), control1: p(0.1359, 0.8237), control2: p(0.1798, 0.8680))
        path.addCurve(to: p(0.4231, 0.9814), control1: p(0.2822, 0.9410), control2: p(0.3517, 0.9696))
        path.addCurve(to: p(0.5016, 0.9874), control1: p(0.4519, 0.9862), control2: p(0.4670, 0.9874))
        path.addCurve(to: p(0.5801, 0.9814), control1: p(0.5362, 0.9874), control2: p(0.5513, 0.9862))
        path.addCurve(to: p(0.9191, 0.7461), control1: p(0.7219, 0.9579), control2: p(0.8456, 0.8721))
        path.addCurve(to: p(0.9461, 0.6918), control1: p(0.9269, 0.7328), control2: p(0.9469, 0.6926))
        path.addCurve(to: p(0.8247, 0.7793), control1: p(0.9459, 0.6916), control2: p(0.8913, 0.7311))
        path.addCurve(to: p(0.7030, 0.8671), control1: p(0.7582, 0.8277), control2: p(0.7034, 0.8672))
        path.addCurve(to: p(0.3916, 0.5842), control1: p(0.7018, 0.8667), control2: p(0.3912, 0.5846))
        path.addCurve(to: p(0.5202, 0.5910), control1: p(0.3918, 0.5841), control2: p(0.4497, 0.5871))
        path.addCurve(to: p(0.6491, 0.5974), control1: p(0.5908, 0.5949), control2: p(0.6488, 0.5977))
        path.addCurve(to: p(0.6790, 0.0437), control1: p(0.6499, 0.5967), control2: p(0.6797, 0.0443))
        path.addCurve(to: p(0.6600, 0.0367), control1: p(0.6788, 0.0435), control2: p(0.6703, 0.0403))
        path.addCurve(to: p(0.5522, 0.0124), control1: p(0.6265, 0.0250), control2: p(0.5887, 0.0165))
        path.addCurve(to: p(0.4731, 0.0104), control1: p(0.5377, 0.0109), control2: p(0.4858, 0.0096))
        path.closeSubpath()
        path.move(to: p(0.4559, 0.2279))
        path.addCurve(to: p(0.4661, 0.3185), control1: p(0.4559, 0.2285), control2: p(0.4605, 0.2691))
        path.addCurve(to: p(0.4760, 0.4083), control1: p(0.4716, 0.3677), control2: p(0.4761, 0.4082))
        path.addCurve(to: p(0.3835, 0.4184), control1: p(0.4754, 0.4087), control2: p(0.3839, 0.4188))
        path.addCurve(to: p(0.3634, 0.2390), control1: p(0.3831, 0.4178), control2: p(0.3633, 0.2417))
        path.addCurve(to: p(0.4057, 0.2324), control1: p(0.3634, 0.2376), control2: p(0.3703, 0.2365))
        path.addCurve(to: p(0.4559, 0.2279), control1: p(0.4499, 0.2272), control2: p(0.4559, 0.2266))
        path.closeSubpath()
        path.move(to: p(0.8108, 0.1258))
        path.addCurve(to: p(0.7980, 0.3668), control1: p(0.8108, 0.1274), control2: p(0.8049, 0.2359))
        path.addCurve(to: p(0.7855, 0.6052), control1: p(0.7909, 0.4977), control2: p(0.7853, 0.6050))
        path.addCurve(to: p(0.9714, 0.6151), control1: p(0.7861, 0.6059), control2: p(0.9709, 0.6158))
        path.addCurve(to: p(0.9818, 0.5587), control1: p(0.9726, 0.6139), control2: p(0.9796, 0.5758))
        path.addCurve(to: p(0.9840, 0.4612), control1: p(0.9847, 0.5361), control2: p(0.9858, 0.4852))
        path.addCurve(to: p(0.9687, 0.3712), control1: p(0.9817, 0.4322), control2: p(0.9761, 0.3990))
        path.addCurve(to: p(0.9542, 0.3264), control1: p(0.9654, 0.3586), control2: p(0.9547, 0.3258))
        path.addCurve(to: p(0.9477, 0.3728), control1: p(0.9540, 0.3265), control2: p(0.9511, 0.3475))
        path.addCurve(to: p(0.9414, 0.4193), control1: p(0.9444, 0.3983), control2: p(0.9415, 0.4191))
        path.addCurve(to: p(0.8969, 0.4137), control1: p(0.9412, 0.4196), control2: p(0.9212, 0.4170))
        path.addCurve(to: p(0.8511, 0.4076), control1: p(0.8726, 0.4103), control2: p(0.8520, 0.4076))
        path.addCurve(to: p(0.8495, 0.4046), control1: p(0.8500, 0.4076), control2: p(0.8495, 0.4066))
        path.addCurve(to: p(0.8733, 0.2265), control1: p(0.8496, 0.4002), control2: p(0.8727, 0.2272))
        path.addCurve(to: p(0.8892, 0.2283), control1: p(0.8737, 0.2263), control2: p(0.8809, 0.2271))
        path.addCurve(to: p(0.9052, 0.2299), control1: p(0.8977, 0.2295), control2: p(0.9048, 0.2302))
        path.addCurve(to: p(0.8651, 0.1761), control1: p(0.9065, 0.2286), control2: p(0.8810, 0.1945))
        path.addCurve(to: p(0.8165, 0.1274), control1: p(0.8544, 0.1639), control2: p(0.8257, 0.1351))
        path.addLine(to: p(0.8108, 0.1226))
        path.addLine(to: p(0.8108, 0.1258))
        path.closeSubpath()
        return path
    }
}

#Preview {
    HStack(spacing: 30) {
        MascotView(size: 96)
        MascotView(size: 96, isActive: true)
    }
    .padding(40)
    .background(Theme.canvas)
}
