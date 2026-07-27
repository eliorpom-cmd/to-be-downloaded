import SwiftUI
import AppKit

/// Hauteur réservée en haut de fenêtre pour les feux tricolores, la barre de
/// titre étant masquée (`.windowStyle(.hiddenTitleBar)`).
enum WindowChrome {
    static let trafficLightInset: CGFloat = 28
}

// MARK: - Miniature 16:9

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

/// Vignette d'une entrée de bibliothèque : miniature YouTube si on la connaît,
/// sinon une image extraite du fichier lui-même, sinon un glyphe.
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

/// Pastille ronde en tête de capsule : la PHOTO DE PROFIL de la chaîne.
///
/// Elle demande une résolution réseau (cf. `ChannelAvatars`), donc elle n'est
/// pas là dès la première image. En attendant, l'initiale de la chaîne — pas
/// la miniature de la vidéo, qui ferait croire à un avatar puis changerait.
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
    /// Apparition d'une ligne de téléchargement : elle se déplie depuis le haut.
    /// Asymétrique — une disparition doit être plus discrète qu'une arrivée,
    /// puisque l'utilisateur en est déjà à autre chose.
    /// Pas de décalage vertical ni de ressort : les deux se cumulaient à la
    /// remise en page de la liste, et l'arrivée se terminait par un à-coup.
    /// Une mise à l'échelle courte et sans rebond suffit à faire remarquer
    /// l'apparition.
    ///
    /// Propriété calculée : `AnyTransition` n'est pas `Sendable`, donc pas
    /// partageable en `static let` sous Swift 6.
    static var appearingCapsule: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.97, anchor: .top)),
            removal: .opacity
        )
    }
}

// MARK: - En-tête de section

struct SectionHeader: View {
    let title: String
    var count: Int?

    var body: some View {
        Text(count.map { "\(title.uppercased()) — \($0)" } ?? title.uppercased())
            .font(Theme.Text.sectionHeader)
            .tracking(0.5)
            .foregroundStyle(Theme.labelSecondary)
    }
}

// MARK: - État vide

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

// MARK: - Bandeau d'information

/// Bandeau neutre : glyphe + message. Aucune couleur sémantique — l'erreur se
/// lit au glyphe et au poids du texte (design system monochrome strict).
struct InlineNotice: View {
    let symbol: String
    let message: String
    /// Action facultative en fin de bandeau (ex. « Update »).
    var actionTitle: String? = nil
    var actionEnabled: Bool = true
    var action: (() -> Void)? = nil

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
        }
        .padding(.vertical, Theme.Space.s8)
        .padding(.horizontal, Theme.Space.s12)
        .background(Theme.fillTertiary, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
    }
}

// MARK: - Bouton d'icône discret

/// Bouton sans chrome, pour les affordances de fin de ligne (··· , ✕, ⟳).
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

// MARK: - Matériau de sidebar

/// `NSVisualEffectView` en mode sidebar : c'est la seule façon d'obtenir la
/// vibrance système exacte quand on ne passe pas par `List(.sidebar)`.
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
