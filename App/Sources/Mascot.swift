import SwiftUI

/// La mascotte ENTIÈRE — la pastille dont la flèche et les yeux sont évidés.
/// C'est la marque de l'app telle qu'on la voit dans le Dock, et c'est elle qui
/// accueille sur l'écran Download.
///
/// L'évidement laisse passer le fond de la fenêtre, qui est translucide (cf.
/// `RootView`) : le dessin respire le matériau derrière lui, comme la pastille
/// de l'icône laisse voir le fond du système. Peinte en `Theme.ink`, elle
/// s'inverse donc avec le thème sans qu'on s'en occupe.
///
/// `MascotShape` seule — la flèche et les yeux, sans la pastille — n'est plus
/// employée nulle part comme icône : partout où l'app se représente elle-même
/// sans passer par `AppIcon.icon`, c'est la pastille entière qu'on montre.
///
/// Volontairement IMMOBILE : le balancement permanent attirait l'œil sans rien
/// dire. `isActive` est conservé pour les appelants, mais n'anime plus rien.
struct MascotView: View {
    /// Côté de la pastille, qui est carrée.
    var size: CGFloat = 44
    var isActive: Bool = false

    var body: some View {
        AppIconShape()
            .fill(Theme.ink)
            .frame(width: size, height: size)
    }
}

/// Rendu AppKit de la mascotte, pour les endroits qui exigent une `NSImage` :
/// barre des menus, notifications.
enum MascotImage {

    /// `viewBox` du SVG produit par `svgPathData()`, dans les mêmes unités.
    static let svgViewBox = "0 0 100 135.02"

    /// `viewBox` du SVG produit par `iconSvgPathData()` : la pastille est
    /// carrée, contrairement à la mascotte seule.
    static let iconSvgViewBox = "0 0 100 100"

    /// Données de tracé SVG (`d="…"`) de la mascotte SEULE — la flèche et les
    /// yeux, sans la pastille — dans une boîte de 100 de large (cf.
    /// `svgViewBox` pour la hauteur).
    ///
    /// Conservée pour les usages typographiques, où le dessin accompagne un
    /// texte au lieu de représenter l'app. Pour l'icône, c'est
    /// `iconSvgPathData()` qu'il faut.
    static func svgPathData(width: CGFloat = 100) -> String {
        pathData(of: MascotShape(),
                 in: CGRect(x: 0, y: 0, width: width, height: width / MascotShape.aspectRatio))
    }

    /// Données de tracé SVG (`d="…"`) de l'ICÔNE : la pastille dont la mascotte
    /// est évidée, dans une boîte carrée de 100 (cf. `iconSvgViewBox`).
    ///
    /// Généré depuis le MÊME `AppIconShape` que l'app : l'icône n'existe qu'à un
    /// seul endroit. Sur la page web elle est peinte en `currentColor`, donc
    /// elle s'inverse tout seule en thème sombre — contrairement à un PNG.
    ///
    /// À rendre en `fill-rule="nonzero"` : la flèche et les yeux sont des
    /// sous-tracés d'orientation inverse, donc des trous.
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

    /// Glyphe de barre des menus : l'ICÔNE, pastille comprise — c'est le contour
    /// qui la fait reconnaître comme l'app du Dock. La mascotte sortie de sa
    /// pastille ne renvoyait à rien.
    ///
    /// 15 pt et non 17 : une forme pleine occupe toute sa boîte, là où un glyphe
    /// évidé n'en remplit qu'une part. À hauteur égale, la pastille écraserait
    /// les symboles voisins du système.
    ///
    /// Rendu dans un bitmap HORS ÉCRAN plutôt que via
    /// `NSImage(size:flipped:drawingHandler:)` : ce dernier peint directement
    /// dans le contexte de destination, où l'on ne maîtrise ni le suréchantil-
    /// lonnage ni les modes de fusion. Ici on choisit l'échelle (3×) pour que
    /// les yeux et l'encoche de la flèche survivent à la réduction.
    ///
    /// Image *template* : macOS la recolore selon le thème de la barre des
    /// menus (clair, sombre, inversion au clic). L'évidement reste transparent,
    /// donc la flèche et les yeux prennent le fond de la barre.
    static func menuBar(height: CGFloat = 15) -> NSImage {
        let scale: CGFloat = 3
        // La pastille est carrée : lui donner une boîte non carrée la déforme.
        let size = NSSize(width: height, height: height)
        guard let context = CGContext(
            data: nil, width: Int(height * scale), height: Int(height * scale),
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return NSImage(size: size) }

        context.scaleBy(x: scale, y: scale)
        // Repère y vers le bas, pour raisonner comme dans le reste de l'UI.
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

/// La mascotte seule : la flèche et les deux yeux, sans la pastille.
///
/// N'est PAS l'icône de l'app — sortie de son contour, la marque ne se
/// reconnaît plus. À réserver aux usages typographiques, où le dessin
/// accompagne un texte ; partout ailleurs, `AppIconShape`.
///
/// Coordonnées normalisées 0…1 sur sa propre boîte englobante, remises à
/// l'échelle du `rect` fourni — respecter `aspectRatio` sous peine de la
/// déformer. Généré depuis `App/Resources/AppIcon.icon/Assets/mascot.svg`.
struct MascotShape: Shape {

    /// Largeur / hauteur du dessin. La mascotte est plus haute que large.
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

/// L'icône de l'app : la pastille dont la mascotte est ÉVIDÉE.
///
/// Le rendu du Dock vient de `App/Resources/AppIcon.icon` (Liquid Glass, compilé
/// par `actool`). Ce tracé est là pour TOUT ce que le bundle ne couvre pas, et
/// c'est lui qu'il faut partout : l'accueil de l'app (`MascotView`), la barre
/// des menus (`MascotImage.menuBar()`), le logo de la page web et l'icône PWA
/// comme le favicon servis par le serveur (cf. `Server/AppIcon`).
///
/// Rempli en non-zero : la flèche et les yeux sont des sous-tracés d'orientation
/// inverse, donc des trous. En even-odd la pastille devient un carré plein.
/// Carrée : lui donner un `rect` non carré la déforme.
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
        // L'icône, telle qu'elle accueille sur l'écran Download, tient la barre
        // des menus et coiffe la page web…
        MascotView(size: 96)
        // …et son intérieur seul, qui ne sert plus d'icône nulle part.
        MascotShape().fill(Theme.ink).frame(width: 96 * MascotShape.aspectRatio, height: 96)
    }
    .padding(40)
    .background(Theme.canvas)
}
