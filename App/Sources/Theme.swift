// TBD — To be downloaded. Copyright (C) 2026 Elior Pommier.
// Licensed under the GNU AGPL v3 or later. See LICENSE and NOTICE.
import SwiftUI
import AppKit

/// Design system: monochrome (no accent color), neutral gray undertone.
/// Hierarchy comes from weight/size/space, not hue.
///
/// The values are an exact copy of the variables from the reference Figma file
/// (collections `Color` and `Layout`): it's the source of truth for design.
/// If a token changes in Figma, it changes here — and nowhere else.
enum Theme {

    // MARK: - Backgrounds

    /// Window background (`bg/window`).
    static let window = adaptive(light: 0xFFFFFF, dark: 0x1E1E1E)

    /// Sidebar background (`bg/sidebar`) — used only where the system
    /// material doesn't apply.
    static let sidebar = adaptive(light: 0xEDEDED, dark: 0x2E2E30)

    /// Card / grouping surface (`bg/card`).
    static let card = adaptive(light: 0xFFFFFF, dark: 0x2A2A2C)

    // MARK: - Fill ramp
    //
    // Neutral translucent gray, like AppKit's `NSColor.systemFill`: the
    // tint follows the background, avoiding muddy flats in dark mode.

    /// `fill/primary` — progress fill, avatars.
    static let fillPrimary = adaptive(light: (0x787880, 0.20), dark: (0x787880, 0.36))
    /// `fill/secondary`
    static let fillSecondary = adaptive(light: (0x787880, 0.12), dark: (0x787880, 0.32))
    /// `fill/tertiary` — background of capsules and fields.
    static let fillTertiary = adaptive(light: (0x767680, 0.08), dark: (0x767680, 0.24))
    /// `fill/quaternary` — most subtle fill (internal cards).
    static let fillQuaternary = adaptive(light: (0x747480, 0.05), dark: (0x767680, 0.18))
    /// `fill/row-hover` — hovered capsule.
    static let rowHover = adaptive(light: (0x787880, 0.18), dark: (0x787880, 0.34))

    // MARK: - Labels

    /// `label/primary`
    static let label = adaptive(light: (0x000000, 0.85), dark: (0xFFFFFF, 1.0))
    /// `label/secondary` — meta, subtitles.
    static let labelSecondary = adaptive(light: (0x000000, 0.50), dark: (0xFFFFFF, 0.55))
    /// `label/tertiary` — placeholders, disabled elements.
    static let labelTertiary = adaptive(light: (0x000000, 0.26), dark: (0xFFFFFF, 0.25))

    // MARK: - Ink (Primary Button)

    /// `ink/fill` — fill of the download button.
    static let ink = adaptive(light: 0x0A0A0A, dark: 0xF5F5F5)
    /// `ink/on-fill` — label placed on `ink`.
    static let inkOn = adaptive(light: 0xFFFFFF, dark: 0x0A0A0A)

    // MARK: - Strokes

    static let separator = adaptive(light: (0x000000, 0.10), dark: (0xFFFFFF, 0.12))
    static let strokeControl = adaptive(light: (0x000000, 0.12), dark: (0xFFFFFF, 0.14))
    /// `stroke/emphasis` — stroke of an error state. **No red**: errors are
    /// signaled by the stroke, icon, and text at full strength.
    static let strokeEmphasis = adaptive(light: (0x0A0A0A, 0.34), dark: (0xF5F5F5, 0.38))
    /// `ring/focus` — keyboard focus halo, neutral (not system blue).
    static let focusRing = adaptive(light: (0x0A0A0A, 0.24), dark: (0xF5F5F5, 0.30))

    // MARK: - Compatibility
    //
    // Old names kept to avoid breaking views that haven't migrated yet
    // (MenuBarExtra, AppIcon, etc.).

    static let canvas = window
    static let surface = card
    static let subtleFill = fillTertiary
    static let inkInverse = inkOn
    static let inkSecondary = labelSecondary

    // MARK: - Layout

    /// Spacing scale (Figma collection `Layout`).
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
        /// Section header in small caps ("DOWNLOADS").
        static let sectionHeader = Font.system(size: 10, weight: .semibold)
    }

    // MARK: - Color Construction

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
    /// Build an sRGB color from a hexadecimal integer 0xRRGGBB.
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

    /// Settings grouping: subtle background + thin border, like the
    /// "grouped boxes" in System Settings.
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

/// Primary action button: `ink` capsule, `ink/on-fill` label.
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
