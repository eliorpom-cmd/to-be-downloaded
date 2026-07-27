import SwiftUI
import AppKit

/// Design system: monochrome (no accent color), neutral gray undertone.
/// Hierarchy comes from weight/size/space, not hue.
///
/// Les valeurs sont la copie exacte des variables du fichier Figma de référence
/// (collections `Color` et `Layout`) : c'est la source de vérité du design.
/// Si un token change dans Figma, il change ici — et nulle part ailleurs.
enum Theme {

    // MARK: - Backgrounds

    /// Fond de fenêtre (`bg/window`).
    static let window = adaptive(light: 0xFFFFFF, dark: 0x1E1E1E)

    /// Fond de sidebar (`bg/sidebar`) — utilisé seulement là où le matériau
    /// système ne s'applique pas.
    static let sidebar = adaptive(light: 0xEDEDED, dark: 0x2E2E30)

    /// Surface de carte / regroupement (`bg/card`).
    static let card = adaptive(light: 0xFFFFFF, dark: 0x2A2A2C)

    // MARK: - Fill ramp
    //
    // Gris neutre translucide, comme les `NSColor.systemFill` d'AppKit : la
    // teinte suit le fond, ce qui évite les aplats sales en thème sombre.

    /// `fill/primary` — remplissage de progression, avatars.
    static let fillPrimary = adaptive(light: (0x787880, 0.20), dark: (0x787880, 0.36))
    /// `fill/secondary`
    static let fillSecondary = adaptive(light: (0x787880, 0.12), dark: (0x787880, 0.32))
    /// `fill/tertiary` — fond des capsules et des champs.
    static let fillTertiary = adaptive(light: (0x767680, 0.08), dark: (0x767680, 0.24))
    /// `fill/quaternary` — fond le plus discret (cartes internes).
    static let fillQuaternary = adaptive(light: (0x747480, 0.05), dark: (0x767680, 0.18))
    /// `fill/row-hover` — capsule survolée.
    static let rowHover = adaptive(light: (0x787880, 0.18), dark: (0x787880, 0.34))

    // MARK: - Labels

    /// `label/primary`
    static let label = adaptive(light: (0x000000, 0.85), dark: (0xFFFFFF, 1.0))
    /// `label/secondary` — meta, sous-titres.
    static let labelSecondary = adaptive(light: (0x000000, 0.50), dark: (0xFFFFFF, 0.55))
    /// `label/tertiary` — placeholders, éléments désactivés.
    static let labelTertiary = adaptive(light: (0x000000, 0.26), dark: (0xFFFFFF, 0.25))

    // MARK: - Ink (bouton primaire)

    /// `ink/fill` — remplissage du bouton de téléchargement.
    static let ink = adaptive(light: 0x0A0A0A, dark: 0xF5F5F5)
    /// `ink/on-fill` — libellé posé sur `ink`.
    static let inkOn = adaptive(light: 0xFFFFFF, dark: 0x0A0A0A)

    // MARK: - Strokes

    static let separator = adaptive(light: (0x000000, 0.10), dark: (0xFFFFFF, 0.12))
    static let strokeControl = adaptive(light: (0x000000, 0.12), dark: (0xFFFFFF, 0.14))
    /// `stroke/emphasis` — liseré d'un état en erreur. **Pas de rouge** : une
    /// erreur se signale par le liseré, l'icône et le texte à pleine force.
    static let strokeEmphasis = adaptive(light: (0x0A0A0A, 0.34), dark: (0xF5F5F5, 0.38))
    /// `ring/focus` — halo de focus clavier, neutre (pas le bleu système).
    static let focusRing = adaptive(light: (0x0A0A0A, 0.24), dark: (0xF5F5F5, 0.30))

    // MARK: - Compatibilité
    //
    // Anciens noms conservés pour ne pas casser les vues qui n'ont pas encore
    // migré (MenuBarExtra, AppIcon…).

    static let canvas = window
    static let surface = card
    static let subtleFill = fillTertiary
    static let inkInverse = inkOn
    static let inkSecondary = labelSecondary

    // MARK: - Layout

    /// Échelle d'espacement (collection Figma `Layout`).
    enum Space {
        static let s2: CGFloat = 2
        static let s4: CGFloat = 4
        static let s6: CGFloat = 6
        static let s8: CGFloat = 8
        static let s10: CGFloat = 10
        static let s12: CGFloat = 12
        static let s16: CGFloat = 16
        static let s20: CGFloat = 20
        static let s24: CGFloat = 24
        static let s32: CGFloat = 32
        static let s40: CGFloat = 40
    }

    enum Spacing {
        static let xs = Space.s8
        static let sm = Space.s12
        static let md = Space.s16
        static let lg = Space.s20
        static let xl = Space.s24
        static let xxl = Space.s32
    }

    enum Radius {
        static let control: CGFloat = 6
        static let field: CGFloat = 8
        static let row: CGFloat = 8
        static let card: CGFloat = 10
        static let sidebarItem: CGFloat = 6
        static let window: CGFloat = 14
    }

    // MARK: - Type ramp (SF Pro, tailles macOS HIG)

    enum Text {
        static let largeTitle = Font.system(size: 26, weight: .regular)
        static let title1 = Font.system(size: 22, weight: .regular)
        static let title2 = Font.system(size: 17, weight: .regular)
        static let title3 = Font.system(size: 15, weight: .semibold)
        static let headline = Font.system(size: 13, weight: .semibold)
        static let body = Font.system(size: 13, weight: .regular)
        static let bodyEmphasized = Font.system(size: 13, weight: .medium)
        static let callout = Font.system(size: 12, weight: .regular)
        static let subheadline = Font.system(size: 11, weight: .regular)
        static let footnote = Font.system(size: 10, weight: .regular)
        static let caption = Font.system(size: 10, weight: .medium)
        /// En-tête de section en petites capitales (« DOWNLOADS »).
        static let sectionHeader = Font.system(size: 10, weight: .semibold)
    }

    // MARK: - Construction des couleurs

    private static func adaptive(light: Int, dark: Int) -> Color {
        adaptive(light: (light, 1.0), dark: (dark, 1.0))
    }

    private static func adaptive(light: (Int, Double), dark: (Int, Double)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(hex: dark.0, alpha: dark.1)
                : NSColor(hex: light.0, alpha: light.1)
        })
    }
}

private extension NSColor {
    /// Construit une couleur sRGB depuis un entier hexadécimal 0xRRGGBB.
    convenience init(hex: Int, alpha: Double = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: CGFloat(alpha)
        )
    }
}

// MARK: - Surfaces

extension View {
    func cardStyle(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    /// Regroupement de réglages : fond discret + liseré fin, comme les
    /// « grouped boxes » des Réglages Système.
    func groupedCard() -> some View {
        self
            .background(Theme.fillQuaternary, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(Theme.separator, lineWidth: 1)
            )
    }
}

// MARK: - Buttons

/// Bouton d'action principal : capsule `ink`, libellé `ink/on-fill`.
struct PrimaryCapsuleButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Text.bodyEmphasized)
            .foregroundStyle(Theme.inkOn)
            .padding(.horizontal, Theme.Space.s16)
            .padding(.vertical, Theme.Space.s8)
            .background(Theme.ink.opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.35), in: Capsule())
    }
}

/// Bouton secondaire : capsule de remplissage neutre.
struct SecondaryCapsuleButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Text.body)
            .foregroundStyle(Theme.label.opacity(isEnabled ? 1 : 0.4))
            .padding(.horizontal, Theme.Space.s12)
            .padding(.vertical, Theme.Space.s6)
            .background(configuration.isPressed ? Theme.fillSecondary : Theme.fillTertiary, in: Capsule())
    }
}

/// Bouton « push » macOS : rectangle arrondi 6pt, hauteur 24.
struct PushButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Text.body)
            .foregroundStyle(Theme.label.opacity(isEnabled ? 1 : 0.35))
            .padding(.horizontal, Theme.Space.s10)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .fill(configuration.isPressed ? Theme.fillSecondary : Theme.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                            .strokeBorder(Theme.strokeControl, lineWidth: 1)
                    )
            )
    }
}

extension ButtonStyle where Self == PrimaryCapsuleButtonStyle {
    static var primaryCapsule: PrimaryCapsuleButtonStyle { PrimaryCapsuleButtonStyle() }
}

extension ButtonStyle where Self == SecondaryCapsuleButtonStyle {
    static var secondaryCapsule: SecondaryCapsuleButtonStyle { SecondaryCapsuleButtonStyle() }
}

extension ButtonStyle where Self == PushButtonStyle {
    static var push: PushButtonStyle { PushButtonStyle() }
}
