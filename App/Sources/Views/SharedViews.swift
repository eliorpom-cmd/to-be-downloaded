// TBD — To Be Downloaded. Copyright (C) 2026 Elior Pommier.
// Licensed under the GNU AGPL v3 or later. See LICENSE and NOTICE.
import SwiftUI
import AppKit

/// Reserved height at the top of the window for traffic lights, with the
/// title bar hidden (`.windowStyle(.hiddenTitleBar)`).
enum WindowChrome {
    static let trafficLightInset: CGFloat = 28
}

// MARK: - 16:9 Thumbnail

struct Thumbnail: View {
    let urlString: String?
    var width: CGFloat
    var height: CGFloat
    var cornerRadius: CGFloat = 6

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Theme.fillSecondary)
            .frame(width: width, height: height)
            .overlay {
                if let urlString, let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image): image.resizable().aspectRatio(contentMode: .fill)
                        case .failure: placeholder
                        default: Color.clear
                        }
                    }
                } else {
                    placeholder
                }
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var placeholder: some View {
        Image(systemName: "play.fill")
            .font(.system(size: max(9, height * 0.3)))
            .foregroundStyle(Theme.labelTertiary)
    }
}

/// Thumbnail for a library entry: YouTube thumbnail if we have it,
/// otherwise an image extracted from the file itself, otherwise a glyph.
struct LibraryThumbnail: View {
    let item: LibraryItem
    var width: CGFloat
    var height: CGFloat

    @State private var extracted: NSImage?

    var body: some View {
        Group {
            if let url = item.thumbnailURL, !url.isEmpty {
                Thumbnail(urlString: url, width: width, height: height)
            } else if let extracted {
                Image(nsImage: extracted)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: width, height: height)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .transition(.opacity)
            } else {
                Thumbnail(urlString: nil, width: width, height: height)
            }
        }
        .animation(.easeOut(duration: 0.2), value: extracted != nil)
        .task(id: item.id) {
            guard item.thumbnailURL == nil || item.thumbnailURL?.isEmpty == true,
                  item.kind == .video, item.fileExists
            else { return }
            extracted = await PosterFrame.image(for: item.id, file: item.fileURL)
        }
    }
}

/// Round tile at the head of a capsule: the PROFILE PHOTO of the channel.
///
/// It requires a network lookup (see `ChannelAvatars`), so it's not there
/// right away. In the meantime, the channel's initial — not the video
/// thumbnail, which would suggest an avatar then change.
struct ChannelAvatar: View {
    let urlString: String?
    var channelName: String?
    var size: CGFloat = 28

    var body: some View {
        Circle()
            .fill(Theme.fillPrimary)
            .frame(width: size, height: size)
            .overlay {
                if let urlString, let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image): image.resizable().aspectRatio(contentMode: .fill)
                        default: placeholder
                        }
                    }
                } else {
                    placeholder
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .animation(.easeOut(duration: 0.2), value: urlString)
    }

    @ViewBuilder
    private var placeholder: some View {
        if let initial {
            Text(initial)
                .font(.system(size: size * 0.42, weight: .medium))
                .foregroundStyle(Theme.labelSecondary)
        } else {
            Image(systemName: "person.fill")
                .font(.system(size: size * 0.4))
                .foregroundStyle(Theme.labelTertiary)
        }
    }

    private var initial: String? {
        guard let first = channelName?.trimmingCharacters(in: .whitespaces).first,
              first.isLetter || first.isNumber
        else { return nil }
        return String(first).uppercased()
    }
}

// MARK: - Transitions

extension AnyTransition {
    /// Download row arrival: it unfolds from the top. Asymmetric — removal
    /// should be more subtle than arrival, since the user is already looking
    /// elsewhere. No vertical offset or spring: both combined with list
    /// relayout, and arrival ended with a stutter. Short scale with no bounce
    /// is enough to make the arrival noticeable.
    ///
    /// Computed property: `AnyTransition` is not `Sendable`, so it can't be
    /// shared as `static let` under Swift 6.
    static var appearingCapsule: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.97, anchor: .top)),
            removal: .opacity
        )
    }
}

// MARK: - Section Header

struct SectionHeader: View {
    let title: String
    var count: Int?

    var body: some View {
        Text(count.map { "\(title.uppercased()) · \($0)" } ?? title.uppercased())
            .font(Theme.Text.sectionHeader)
            .tracking(0.5)
            .foregroundStyle(Theme.labelSecondary)
    }
}

// MARK: - Empty State

struct EmptyState: View {
    let symbol: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.labelTertiary)
            Spacer().frame(height: Theme.Space.s12)
            Text(title)
                .font(Theme.Text.bodyEmphasized)
                .foregroundStyle(Theme.label)
            Spacer().frame(height: Theme.Space.s4)
            Text(subtitle)
                .font(Theme.Text.body)
                .foregroundStyle(Theme.labelSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 300)
        }
    }
}

// MARK: - Inline Notice

/// Neutral banner: glyph + message. No semantic color — error reads from the
/// glyph and text weight (strictly monochrome design system).
struct InlineNotice: View {
    let symbol: String
    let message: String
    /// Optional action at the end of the banner (e.g., "Update").
    var actionTitle: String? = nil
    var actionEnabled: Bool = true
    var action: (() -> Void)? = nil
    /// Second action, more subtle (e.g., "Discard").
    var secondaryTitle: String? = nil
    var secondaryAction: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: Theme.Space.s8) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .foregroundStyle(Theme.labelSecondary)
            Text(message)
                .font(Theme.Text.body)
                .foregroundStyle(Theme.label)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.plain)
                    .font(Theme.Text.bodyEmphasized)
                    .foregroundStyle(actionEnabled ? Theme.label : Theme.labelTertiary)
                    .disabled(!actionEnabled)
            }
            if let secondaryTitle, let secondaryAction {
                Button(secondaryTitle, action: secondaryAction)
                    .buttonStyle(.plain)
                    .font(Theme.Text.body)
                    .foregroundStyle(Theme.labelSecondary)
            }
        }
        .padding(.vertical, Theme.Space.s8)
        .padding(.horizontal, Theme.Space.s12)
        .background(Theme.fillTertiary, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
    }
}

// MARK: - Subtle Icon Button

/// Button with no chrome, for end-of-line affordances (··· , ✕, ⟳).
struct IconButton: View {
    let symbol: String
    var size: CGFloat = 13
    var help: String = ""
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size))
                .foregroundStyle(hovering ? Theme.label : Theme.labelSecondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

// MARK: - Brand Logo

/// Icon button whose glyph is a BRAND LOGO, loaded from an SVG in the bundle
/// (`Resources/Logos`).
///
/// Why not SF Symbol: the system font has no brands — no GitHub, no Instagram.
/// Why not a set of PNGs: `NSImage` reads SVG since macOS 13, so one file per
/// logo suffices, sharp at any size. `isTemplate` leaves color to the theme,
/// like an SF Symbol.
///
/// A system glyph fallback is in place: if a macOS version rejected SVG,
/// a link with no icon would be an invisible empty square.
struct BrandLogoButton: View {
    let logo: String
    let fallbackSymbol: String
    var size: CGFloat = 14
    var help: String = ""
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            glyph
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }

    @ViewBuilder
    private var glyph: some View {
        if let image = BrandLogo.image(named: logo) {
            Image(nsImage: image)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .foregroundStyle(hovering ? Theme.label : Theme.labelSecondary)
        } else {
            Image(systemName: fallbackSymbol)
                .font(.system(size: size))
                .foregroundStyle(hovering ? Theme.label : Theme.labelSecondary)
        }
    }
}

/// Logo cache: `body` is reevaluated on every hover, and re-reading and
/// re-parsing an SVG every frame would be pure waste.
@MainActor
private enum BrandLogo {
    private static var cache: [String: NSImage?] = [:]

    static func image(named name: String) -> NSImage? {
        if let cached = cache[name] { return cached }
        let image = load(name)
        cache[name] = image
        return image
    }

    private static func load(_ name: String) -> NSImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "svg",
                                        subdirectory: "Logos"),
              let image = NSImage(contentsOf: url)
        else { return nil }
        // Make the logo tintable: it will follow `foregroundStyle`, thus the theme.
        image.isTemplate = true
        return image
    }
}

// MARK: - FFmpeg Picker

/// Open panel for "use the FFmpeg I already have". Shared by the first-launch
/// screens, the Download screen's setup card and Settings — three places that
/// ask the same question and must ask it the same way.
@MainActor
enum FFmpegPicker {
    static func choose(startingAt directory: URL?) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        // Homebrew lives under /opt and /usr, which the panel hides by default.
        panel.showsHiddenFiles = true
        panel.prompt = "Use This FFmpeg"
        panel.message = "Pick the ffmpeg executable."
        panel.directoryURL = directory ?? URL(fileURLWithPath: "/opt/homebrew/bin")
        return panel.runModal() == .OK ? panel.url : nil
    }
}

// MARK: - Sidebar Material

/// `NSVisualEffectView` in sidebar mode: the only way to get the exact
/// system vibrancy when not using `List(.sidebar)`.
struct SidebarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// Translucent window background, like Terminal's.
///
/// `.underWindowBackground` in `behindWindow`: the blur captures what's
/// BEHIND the window. A veil of the background color is laid on top — without
/// it, text would lose contrast when a bright image passes behind, and the
/// app's monochrome doesn't forgive that. Adjusting this veil makes the
/// difference between "subtle" and "unreadable".
struct WindowMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
