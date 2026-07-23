import SwiftUI
import AppKit

/// Design system: monochrome (no accent color), neutral gray undertone.
/// Hierarchy comes from weight/size/space, not hue. See design-spec discussion.
enum Theme {

    // MARK: - Palette
    //
    // Design system extrait des captures : monochrome strict, gris NEUTRE pur,
    // hiérarchie par typo/espace et non par couleur. Valeurs figées en hex pour
    // rester identiques entre l'UI native et la page web servie en LAN.

    /// Window/app background — gris très clair (light) / quasi-noir (dark).
    static let canvas = Color(nsColor: adaptive(light: 0xF2F2F4, dark: 0x0B0B0C))

    /// Card / control surface — blanc (light) / gris foncé (dark).
    static let surface = Color(nsColor: adaptive(light: 0xFFFFFF, dark: 0x1C1C1E))

    /// Fill for secondary buttons and subtle input backgrounds.
    static let subtleFill = Color(nsColor: adaptive(light: 0xE8E8EC, dark: 0x2C2C2E))

    /// Primary text/icon/button-fill color — quasi-noir (light) / quasi-blanc (dark).
    static let ink = Color(nsColor: adaptive(light: 0x0A0A0A, dark: 0xF5F5F5))

    /// Label color to use on top of an `ink`-filled surface.
    static let inkInverse = Color(nsColor: adaptive(light: 0xFFFFFF, dark: 0x0A0A0A))

    /// Secondary/meta text — gris moyen neutre.
    static let inkSecondary = Color(nsColor: adaptive(light: 0x8E8E93, dark: 0x8E8E93))

    private static func adaptive(light: Int, dark: Int) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(hex: dark) : NSColor(hex: light)
        }
    }

    // MARK: - Spacing (8pt grid)

    enum Spacing {
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 20
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    // MARK: - Radius

    enum Radius {
        static let card: CGFloat = 20
        static let control: CGFloat = 12
    }
}

private extension NSColor {
    /// Construit une couleur sRGB depuis un entier hexadécimal 0xRRGGBB.
    convenience init(hex: Int) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

// MARK: - Card surface

extension View {
    func cardStyle(padding: CGFloat = Theme.Spacing.lg) -> some View {
        self
            .padding(padding)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }
}

// MARK: - Buttons

struct PrimaryCapsuleButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Theme.inkInverse)
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.sm)
            .background(Theme.ink.opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.35), in: Capsule())
    }
}

struct SecondaryCapsuleButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.ink.opacity(isEnabled ? 1 : 0.4))
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.xs)
            .background(Theme.subtleFill.opacity(configuration.isPressed ? 0.7 : 1), in: Capsule())
    }
}

extension ButtonStyle where Self == PrimaryCapsuleButtonStyle {
    static var primaryCapsule: PrimaryCapsuleButtonStyle { PrimaryCapsuleButtonStyle() }
}

extension ButtonStyle where Self == SecondaryCapsuleButtonStyle {
    static var secondaryCapsule: SecondaryCapsuleButtonStyle { SecondaryCapsuleButtonStyle() }
}
