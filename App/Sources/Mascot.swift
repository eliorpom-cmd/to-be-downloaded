// TBD — To Be Downloaded. Copyright (C) 2026 Elior Pommier.
// Licensed under the GNU AGPL v3 or later. See LICENSE and NOTICE.
import SwiftUI

/// The ENTIRE mascot — the tile with the arrow and eyes hollowed out.
/// It is the app's mark as seen in the Dock, and it is what
/// welcomes on the Download screen.
///
/// The hollowed-out area lets the window background show through, which is
/// translucent (see `RootView`): the shape breathes the material behind it,
/// just as the icon tile lets the system background show. Painted in
/// `Theme.ink`, it inverts with the theme without any extra work.
///
/// `MascotShape` alone — the arrow and eyes, without the tile — is no longer
/// used anywhere as an icon: wherever the app represents itself without going
/// through `AppIcon.icon`, we show the entire tile.
///
/// Intentionally STILL: the permanent swaying caught the eye without saying
/// anything. `isActive` is kept for callers, but doesn't animate anything.
struct MascotView: View {
    /// Side of the tile, which is square.
    var size: CGFloat = 44
    var isActive: Bool = false

    var body: some View {
        AppIconShape()
            .fill(Theme.ink)
            .frame(width: size, height: size)
    }
}

/// AppKit rendering of the mascot, for places that require an `NSImage`:
/// menu bar, notifications.
enum MascotImage {

    /// `viewBox` of the SVG produced by `svgPathData()`, in the same units.
    static let svgViewBox = "0 0 100 135.02"

    /// `viewBox` of the SVG produced by `iconSvgPathData()`: the tile is
    /// square, unlike the mascot alone.
    static let iconSvgViewBox = "0 0 100 100"

    /// SVG path data (`d="…"`) of the mascot ALONE — the arrow and
    /// eyes, without the tile — in a box 100 units wide (see
    /// `svgViewBox` for height).
    ///
    /// Kept for typographic use, where the shape accompanies text instead of
    /// representing the app. For the icon, use `iconSvgPathData()` instead.
    static func svgPathData(width: CGFloat = 100) -> String {
        pathData(of: MascotShape(),
                 in: CGRect(x: 0, y: 0, width: width, height: width / MascotShape.aspectRatio))
    }

    /// SVG path data (`d="…"`) of the ICON: the tile with the mascot
    /// hollowed out, in a 100×100 square box (see `iconSvgViewBox`).
    ///
    /// Generated from the SAME `AppIconShape` as the app: the icon exists in
    /// only one place. On the web page it is painted in `currentColor`, so
    /// it inverts itself in dark mode — unlike a PNG.
    ///
    /// Render with `fill-rule="nonzero"`: the arrow and eyes are
    /// sub-paths with inverse winding, so they are holes.
    static func iconSvgPathData(width: CGFloat = 100) -> String {
        pathData(of: AppIconShape(), in: CGRect(x: 0, y: 0, width: width, height: width))
    }

    private static func pathData(of shape: some Shape, in rect: CGRect) -> String {
        var commands: [String] = []
        func n(_ value: CGFloat) -> String { String(format: "%.2f", value) }

        shape.path(in: rect).cgPath.applyWithBlock { element in
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

    /// Menu bar glyph: the ICON, tile included — it is the outline
    /// that makes it recognizable as the Dock app. The mascot alone, outside
    /// its tile, means nothing.
    ///
    /// 15 pt, not 17: a filled shape occupies its entire box, whereas a
    /// hollowed-out glyph fills only part of it. At equal height, the tile
    /// would crush the neighboring system symbols.
    ///
    /// Rendered in an OFF-SCREEN bitmap rather than via
    /// `NSImage(size:flipped:drawingHandler:)`: the latter paints directly
    /// into the destination context, where we control neither resampling
    /// nor blend modes. Here we choose the scale (3×) so that
    /// the eyes and the arrow's notch survive reduction.
    ///
    /// *Template* image: macOS recolors it according to the menu bar theme
    /// (light, dark, inverted on click). The hollowed-out area stays
    /// transparent, so the arrow and eyes take the bar's background.
    static func menuBar(height: CGFloat = 15) -> NSImage {
        let scale: CGFloat = 3
        // The tile is square: giving it a non-square box deforms it.
        let size = NSSize(width: height, height: height)
        guard let context = CGContext(
            data: nil, width: Int(height * scale), height: Int(height * scale),
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return NSImage(size: size) }

        context.scaleBy(x: scale, y: scale)
        // y coordinate space pointing down, to reason like the rest of the UI.
        context.translateBy(x: 0, y: height)
        context.scaleBy(x: 1, y: -1)
        context.setShouldAntialias(true)

        context.addPath(AppIconShape().path(in: CGRect(origin: .zero, size: size)).cgPath)
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fillPath(using: .winding)

        guard let cgImage = context.makeImage() else { return NSImage(size: size) }
        let image = NSImage(cgImage: cgImage, size: size)
        image.isTemplate = true
        return image
    }
}

/// The mascot alone: the arrow and two eyes, without the tile.
///
/// NOT the app icon — out of its outline, the mark is no longer
/// recognizable. Reserve for typographic use, where the shape
/// accompanies text; everywhere else, use `AppIconShape`.
///
/// Normalized coordinates 0…1 within its own bounding box, scaled to
/// the provided `rect` — respect `aspectRatio` or it will be distorted.
/// Generated from `App/Resources/AppIcon.icon/Assets/mascot.svg`.
struct MascotShape: Shape {

    /// Width / height of the shape. The mascot is taller than it is wide.
    static let aspectRatio: CGFloat = 0.7406

    func path(in rect: CGRect) -> Path {
        func p(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        var path = Path()
        path.move(to: p(0.4138, 0.7523))
        path.addLine(to: p(0.0709, 0.6773))
        path.addCurve(to: p(0.0486, 0.7068), control1: p(0.0470, 0.6721), control2: p(0.0301, 0.6945))
        path.addLine(to: p(0.4812, 0.9955))
        path.addCurve(to: p(0.5106, 0.9967), control1: p(0.4894, 1.0010), control2: p(0.5017, 1.0015))
        path.addLine(to: p(0.9830, 0.7442))
        path.addCurve(to: p(0.9652, 0.7131), control1: p(1.0032, 0.7335), control2: p(0.9897, 0.7099))
        path.addLine(to: p(0.6059, 0.7610))
        path.addLine(to: p(0.6616, 0.0000))
        path.addLine(to: p(0.4688, 0.0000))
        path.closeSubpath()
        path.move(to: p(0.1298, 0.2202))
        path.addCurve(to: p(0.0860, 0.2208), control1: p(0.1205, 0.2177), control2: p(0.1090, 0.2187))
        path.addLine(to: p(0.0605, 0.2232))
        path.addCurve(to: p(0.0177, 0.2304), control1: p(0.0375, 0.2252), control2: p(0.0260, 0.2263))
        path.addCurve(to: p(0.0020, 0.2453), control1: p(0.0105, 0.2340), control2: p(0.0050, 0.2392))
        path.addCurve(to: p(0.0028, 0.2778), control1: p(-0.0014, 0.2522), control2: p(0.0000, 0.2608))
        path.addLine(to: p(0.0241, 0.4061))
        path.addCurve(to: p(0.0339, 0.4377), control1: p(0.0269, 0.4231), control2: p(0.0283, 0.4316))
        path.addCurve(to: p(0.0540, 0.4494), control1: p(0.0388, 0.4431), control2: p(0.0458, 0.4472))
        path.addCurve(to: p(0.0979, 0.4488), control1: p(0.0634, 0.4519), control2: p(0.0749, 0.4509))
        path.addLine(to: p(0.1234, 0.4465))
        path.addCurve(to: p(0.1661, 0.4392), control1: p(0.1464, 0.4444), control2: p(0.1579, 0.4433))
        path.addCurve(to: p(0.1818, 0.4243), control1: p(0.1733, 0.4356), control2: p(0.1789, 0.4304))
        path.addCurve(to: p(0.1810, 0.3918), control1: p(0.1852, 0.4174), control2: p(0.1838, 0.4089))
        path.addLine(to: p(0.1597, 0.2635))
        path.addCurve(to: p(0.1499, 0.2319), control1: p(0.1569, 0.2465), control2: p(0.1555, 0.2380))
        path.addCurve(to: p(0.1298, 0.2202), control1: p(0.1451, 0.2265), control2: p(0.1380, 0.2224))
        path.closeSubpath()
        path.move(to: p(0.9146, 0.2205))
        path.addCurve(to: p(0.8708, 0.2195), control1: p(0.8916, 0.2182), control2: p(0.8801, 0.2171))
        path.addCurve(to: p(0.8504, 0.2310), control1: p(0.8625, 0.2216), control2: p(0.8554, 0.2257))
        path.addCurve(to: p(0.8401, 0.2626), control1: p(0.8448, 0.2370), control2: p(0.8432, 0.2455))
        path.addLine(to: p(0.8169, 0.3906))
        path.addCurve(to: p(0.8155, 0.4231), control1: p(0.8138, 0.4077), control2: p(0.8122, 0.4162))
        path.addCurve(to: p(0.8310, 0.4382), control1: p(0.8184, 0.4292), control2: p(0.8238, 0.4345))
        path.addCurve(to: p(0.8736, 0.4458), control1: p(0.8392, 0.4424), control2: p(0.8507, 0.4435))
        path.addLine(to: p(0.8991, 0.4483))
        path.addCurve(to: p(0.9429, 0.4493), control1: p(0.9221, 0.4506), control2: p(0.9335, 0.4518))
        path.addCurve(to: p(0.9632, 0.4378), control1: p(0.9512, 0.4472), control2: p(0.9583, 0.4432))
        path.addCurve(to: p(0.9735, 0.4063), control1: p(0.9689, 0.4318), control2: p(0.9704, 0.4233))
        path.addLine(to: p(0.9968, 0.2782))
        path.addCurve(to: p(0.9982, 0.2457), control1: p(0.9999, 0.2612), control2: p(1.0015, 0.2527))
        path.addCurve(to: p(0.9827, 0.2307), control1: p(0.9953, 0.2396), control2: p(0.9898, 0.2343))
        path.addCurve(to: p(0.9400, 0.2230), control1: p(0.9745, 0.2265), control2: p(0.9630, 0.2253))
        path.addLine(to: p(0.9146, 0.2205))
        path.closeSubpath()
        return path
    }
}

/// The app icon: the tile with the mascot HOLLOWED OUT.
///
/// The Dock rendering comes from `App/Resources/AppIcon.icon` (Liquid Glass,
/// compiled by `actool`). This path is here for EVERYTHING the bundle doesn't
/// cover, and it's the one that must be used everywhere: the app welcome
/// screen (`MascotView`), the menu bar (`MascotImage.menuBar()`), the web page
/// logo and PWA icon, as well as the favicon served by the server (see
/// `Server/AppIcon`).
///
/// Filled with nonzero winding: the arrow and eyes are sub-paths with inverse
/// winding, so they are holes. With even-odd winding, the tile becomes a solid
/// square. Square: giving it a non-square `rect` deforms it.
struct AppIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        func p(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        var path = Path()
        path.move(to: p(0.4489, 0.6534))
        path.addLine(to: p(0.2283, 0.5883))
        path.addCurve(to: p(0.2140, 0.6139), control1: p(0.2130, 0.5838), control2: p(0.2021, 0.6032))
        path.addLine(to: p(0.4923, 0.8647))
        path.addCurve(to: p(0.5112, 0.8657), control1: p(0.4976, 0.8694), control2: p(0.5055, 0.8699))
        path.addLine(to: p(0.8151, 0.6464))
        path.addCurve(to: p(0.8037, 0.6194), control1: p(0.8281, 0.6370), control2: p(0.8194, 0.6166))
        path.addLine(to: p(0.5726, 0.6610))
        path.addLine(to: p(0.6084, 0.0000))
        path.addLine(to: p(0.6537, 0.0000))
        path.addCurve(to: p(0.8818, 0.0236), control1: p(0.7749, 0.0000), control2: p(0.8355, 0.0000))
        path.addCurve(to: p(0.9764, 0.1182), control1: p(0.9225, 0.0443), control2: p(0.9557, 0.0775))
        path.addCurve(to: p(1.0000, 0.3463), control1: p(1.0000, 0.1645), control2: p(1.0000, 0.2251))
        path.addLine(to: p(1.0000, 0.6537))
        path.addCurve(to: p(0.9764, 0.8818), control1: p(1.0000, 0.7749), control2: p(1.0000, 0.8355))
        path.addCurve(to: p(0.8818, 0.9764), control1: p(0.9557, 0.9225), control2: p(0.9225, 0.9557))
        path.addCurve(to: p(0.6537, 1.0000), control1: p(0.8355, 1.0000), control2: p(0.7749, 1.0000))
        path.addLine(to: p(0.3463, 1.0000))
        path.addCurve(to: p(0.1182, 0.9764), control1: p(0.2251, 1.0000), control2: p(0.1645, 1.0000))
        path.addCurve(to: p(0.0236, 0.8818), control1: p(0.0775, 0.9557), control2: p(0.0443, 0.9225))
        path.addCurve(to: p(0.0000, 0.6537), control1: p(0.0000, 0.8355), control2: p(0.0000, 0.7749))
        path.addLine(to: p(0.0000, 0.3463))
        path.addCurve(to: p(0.0236, 0.1182), control1: p(0.0000, 0.2251), control2: p(0.0000, 0.1645))
        path.addCurve(to: p(0.1182, 0.0236), control1: p(0.0443, 0.0775), control2: p(0.0775, 0.0443))
        path.addCurve(to: p(0.3463, 0.0000), control1: p(0.1645, 0.0000), control2: p(0.2251, 0.0000))
        path.addLine(to: p(0.4844, 0.0000))
        path.addLine(to: p(0.4489, 0.6534))
        path.closeSubpath()
        path.move(to: p(0.2663, 0.1913))
        path.addCurve(to: p(0.2381, 0.1918), control1: p(0.2603, 0.1891), control2: p(0.2529, 0.1900))
        path.addLine(to: p(0.2217, 0.1938))
        path.addCurve(to: p(0.1942, 0.2001), control1: p(0.2069, 0.1956), control2: p(0.1995, 0.1965))
        path.addCurve(to: p(0.1840, 0.2131), control1: p(0.1895, 0.2033), control2: p(0.1860, 0.2078))
        path.addCurve(to: p(0.1846, 0.2413), control1: p(0.1819, 0.2191), control2: p(0.1828, 0.2265))
        path.addLine(to: p(0.1983, 0.3527))
        path.addCurve(to: p(0.2046, 0.3802), control1: p(0.2001, 0.3675), control2: p(0.2010, 0.3749))
        path.addCurve(to: p(0.2175, 0.3903), control1: p(0.2077, 0.3849), control2: p(0.2123, 0.3884))
        path.addCurve(to: p(0.2457, 0.3898), control1: p(0.2235, 0.3925), control2: p(0.2309, 0.3916))
        path.addLine(to: p(0.2621, 0.3878))
        path.addCurve(to: p(0.2896, 0.3815), control1: p(0.2769, 0.3860), control2: p(0.2843, 0.3851))
        path.addCurve(to: p(0.2997, 0.3685), control1: p(0.2943, 0.3783), control2: p(0.2978, 0.3738))
        path.addCurve(to: p(0.2992, 0.3403), control1: p(0.3019, 0.3625), control2: p(0.3010, 0.3551))
        path.addLine(to: p(0.2855, 0.2289))
        path.addCurve(to: p(0.2792, 0.2014), control1: p(0.2837, 0.2141), control2: p(0.2828, 0.2067))
        path.addCurve(to: p(0.2663, 0.1913), control1: p(0.2761, 0.1967), control2: p(0.2715, 0.1932))
        path.closeSubpath()
        path.move(to: p(0.7711, 0.1915))
        path.addCurve(to: p(0.7429, 0.1906), control1: p(0.7563, 0.1895), control2: p(0.7489, 0.1885))
        path.addCurve(to: p(0.7298, 0.2006), control1: p(0.7376, 0.1925), control2: p(0.7330, 0.1960))
        path.addCurve(to: p(0.7232, 0.2280), control1: p(0.7262, 0.2059), control2: p(0.7252, 0.2133))
        path.addLine(to: p(0.7082, 0.3393))
        path.addCurve(to: p(0.7074, 0.3675), control1: p(0.7062, 0.3541), control2: p(0.7052, 0.3615))
        path.addCurve(to: p(0.7173, 0.3806), control1: p(0.7092, 0.3728), control2: p(0.7127, 0.3774))
        path.addCurve(to: p(0.7448, 0.3872), control1: p(0.7226, 0.3842), control2: p(0.7300, 0.3852))
        path.addLine(to: p(0.7611, 0.3894))
        path.addCurve(to: p(0.7893, 0.3903), control1: p(0.7759, 0.3914), control2: p(0.7833, 0.3924))
        path.addCurve(to: p(0.8024, 0.3803), control1: p(0.7946, 0.3884), control2: p(0.7992, 0.3849))
        path.addCurve(to: p(0.8090, 0.3529), control1: p(0.8060, 0.3750), control2: p(0.8070, 0.3676))
        path.addLine(to: p(0.8240, 0.2416))
        path.addCurve(to: p(0.8249, 0.2134), control1: p(0.8260, 0.2268), control2: p(0.8270, 0.2194))
        path.addCurve(to: p(0.8149, 0.2003), control1: p(0.8230, 0.2081), control2: p(0.8195, 0.2035))
        path.addCurve(to: p(0.7875, 0.1937), control1: p(0.8096, 0.1967), control2: p(0.8022, 0.1957))
        path.addLine(to: p(0.7711, 0.1915))
        path.closeSubpath()
        return path
    }
}

#Preview {
    HStack(spacing: 30) {
        // The icon as it welcomes on the Download screen, appears in the menu
        // bar, and tops the web page…
        MascotView(size: 96)
        // …and its interior alone, which no longer serves as an icon anywhere.
        MascotShape().fill(Theme.ink).frame(width: 96 * MascotShape.aspectRatio, height: 96)
    }
    .padding(40)
    .background(Theme.canvas)
}
