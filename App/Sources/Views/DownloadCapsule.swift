import SwiftUI
import AppKit

/// La ligne de téléchargement de la maquette : une capsule dont le **fond se
/// remplit** au fil de la progression, avec la vignette de la chaîne à gauche,
/// le titre, la meta à droite et une affordance contextuelle.
///
/// Partagée par l'écran Download (session) et l'onglet Library (section
/// « Downloading »).
struct DownloadCapsule: View {
    let job: DownloadJob
    /// En file derrière d'autres, plutôt qu'en train de se préparer.
    var waiting: Bool = false
    let onTogglePause: () -> Void
    let onCancel: () -> Void
    let onRetry: () -> Void
    /// Clic sur la ligne terminée.
    let onOpen: () -> Void
    /// Clic sur la coche : retire la ligne de la liste de la session.
    var onDismiss: () -> Void = {}

    @State private var hovering = false
    @State private var sweep = false

    private var isFailed: Bool { job.state == .failed }

    /// yt-dlp est lancé mais n'a encore rien émis : il se déballe et interroge
    /// YouTube. Rien à mesurer, mais il faut que ça se voie.
    private var isPreparing: Bool { job.state == .queued && !waiting }

    var body: some View {
        ZStack(alignment: .leading) {
            // Fond de piste.
            Capsule().fill(hovering ? Theme.rowHover : Theme.fillTertiary)

            // Remplissage de progression, découpé par la capsule.
            if let fraction = job.progressFraction {
                GeometryReader { geo in
                    Rectangle()
                        .fill(Theme.fillPrimary)
                        .frame(width: max(0, min(1, fraction)) * geo.size.width)
                        .animation(.easeOut(duration: 0.25), value: fraction)
                }
                .clipShape(Capsule())
            }

            // Balayage indéterminé pendant la préparation : la seule façon
            // honnête de dire « ça travaille » quand on ne peut rien mesurer.
            if isPreparing {
                GeometryReader { geo in
                    LinearGradient(
                        colors: [.clear, Theme.fillPrimary, .clear],
                        startPoint: .leading, endPoint: .trailing)
                        .frame(width: geo.size.width * 0.45)
                        .offset(x: sweep ? geo.size.width : -geo.size.width * 0.45)
                }
                .clipShape(Capsule())
                .allowsHitTesting(false)
                .onAppear {
                    withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                        sweep = true
                    }
                }
            }

            HStack(spacing: Theme.Space.s10) {
                ChannelAvatar(urlString: job.metadata?.channelAvatarURL,
                              channelName: job.metadata?.channel)

                // Tant que le titre n'est pas connu, un trait neutre plutôt que
                // l'URL brute : elle s'affichait puis sautait au vrai titre.
                if job.metadata?.title == nil, job.state.isActive {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Theme.fillSecondary)
                        .frame(width: 132, height: 9)
                        .transition(.opacity)
                } else {
                    Text(job.displayTitle)
                        .font(Theme.Text.body)
                        .foregroundStyle(job.state == .paused ? Theme.labelSecondary : Theme.label)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .transition(.opacity)
                }

                Spacer(minLength: Theme.Space.s8)

                // Largeur RÉSERVÉE et chiffres à chasse fixe : le texte change à
                // chaque rafraîchissement, et sans cela toute la ligne — titre
                // compris — se décalait à chaque image.
                Text(metaText)
                    .font(Theme.Text.caption)
                    .monospacedDigit()
                    .foregroundStyle(isFailed ? Theme.label : Theme.labelSecondary)
                    .lineLimit(1)
                    .frame(minWidth: metaWidth, alignment: .trailing)

                trailing
            }
            .padding(.leading, Theme.Space.s8)
            .padding(.trailing, Theme.Space.s12)
        }
        .frame(height: 44)
        .overlay {
            // Un échec se signale par un liseré, pas par une couleur.
            if isFailed {
                Capsule().strokeBorder(Theme.strokeEmphasis, lineWidth: 1)
            }
        }
        .animation(.easeOut(duration: 0.25), value: job.metadata?.title)
        .contentShape(Capsule())
        .onHover { hovering = $0 }
        // Toute la capsule est cliquable une fois le fichier là.
        // Une ligne terminée mène à la bibliothèque, pas au Finder : on reste
        // dans l'app, où la vidéo a une fiche, une vignette et un menu.
        .onTapGesture {
            if job.state == .completed { onOpen() }
        }
        // Un fichier terminé se glisse vers le Finder ou n'importe quelle app.
        .onDrag {
            guard job.state == .completed, let url = job.fileURL,
                  let provider = NSItemProvider(contentsOf: url)
            else { return NSItemProvider() }
            return provider
        }
        .contextMenu { menu }
        .help(helpText)
    }

    /// Le débit et le temps restant ne tiennent plus dans la ligne : ils
    /// mangeaient la place du titre, qui est la seule information qu'on
    /// cherche vraiment du regard. Ils vivent ici, comme le libellé d'un
    /// bouton — visibles quand on les demande.
    private var helpText: String {
        switch job.state {
        case .failed:
            return job.errorMessage ?? "Failed"
        case .completed:
            return "Show in Library — \(job.displayTitle)"
        case .queued:
            return waiting ? "Waiting for a free slot" : "Starting the download engine…"
        case .downloading, .paused:
            var parts = [job.displayTitle]
            let speed = Format.speed(job.progress?.speed)
            let eta = Format.eta(job.progress?.eta)
            if !speed.isEmpty { parts.append(speed) }
            if !eta.isEmpty { parts.append(eta) }
            if let total = job.progress?.totalBytes { parts.append(Format.bytes(total)) }
            return parts.joined(separator: " · ")
        default:
            return job.displayTitle
        }
    }

    // MARK: - Meta

    /// Place réservée à la meta pendant qu'elle bouge. Étroite : elle ne porte
    /// plus qu'un pourcentage, le reste est passé en info-bulle.
    private var metaWidth: CGFloat? {
        switch job.state {
        case .downloading, .paused: return 38
        case .queued, .merging:     return 74
        case .completed, .failed, .cancelled: return nil
        }
    }

    private var metaText: String {
        switch job.state {
        case .queued:
            return waiting ? "Waiting…" : "Preparing…"
        case .downloading:
            // Le pourcentage suit la barre unique, pas le flux en cours : les
            // deux doivent raconter la même histoire.
            return "\(Int(job.overallProgress * 100))%"
        case .paused:
            return "\(Int(job.overallProgress * 100))%"
        case .merging:
            return "Finishing up…"
        case .completed:
            return job.fileSize.map(Format.bytes) ?? "Done"
        case .failed:
            return "Failed · Retry"
        case .cancelled:
            return "Cancelled"
        }
    }

    // MARK: - Affordance de fin de ligne

    @ViewBuilder
    private var trailing: some View {
        switch job.state {
        case .queued, .downloading, .paused:
            // Une seule affordance, toujours la même : annuler. La pause reste
            // au menu contextuel — un bouton qui change de sens selon le survol
            // fait hésiter, et personne ne met un téléchargement en pause aussi
            // souvent qu'il l'abandonne.
            IconButton(symbol: "xmark.circle.fill", size: 15, help: "Cancel", action: onCancel)
        case .merging:
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.7)
                .frame(width: 22, height: 22)
        case .completed:
            IconButton(symbol: "checkmark.circle.fill", size: 15,
                       help: "Remove from this list — the file stays on disk",
                       action: onDismiss)
        case .failed, .cancelled:
            IconButton(symbol: "arrow.clockwise", size: 13, help: "Try again", action: onRetry)
        }
    }

    // MARK: - Menu contextuel

    @ViewBuilder
    private var menu: some View {
        if job.state == .completed, let url = job.fileURL {
            Button("Quick Look") { QuickLook.shared.toggle(url) }
            Button("Play") { FileOpener.play(url) }
            Button("Reveal in Finder") { FileOpener.reveal(url) }
            Divider()
        }
        if job.state == .downloading || job.state == .queued {
            Button("Pause", action: onTogglePause)
        }
        if job.state == .paused {
            Button("Resume", action: onTogglePause)
        }
        Button("Copy Link") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(job.url, forType: .string)
        }
        Button("Copy Title") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(job.displayTitle, forType: .string)
        }
        if job.state == .failed || job.state == .cancelled {
            Button("Download Again", action: onRetry)
        }
        if job.state.isActive {
            Divider()
            Button("Cancel", action: onCancel)
        }
    }
}

// MARK: - Construction depuis le manager

extension DownloadCapsule {
    /// Raccourci : câble les actions sur le manager pour un job donné.
    /// `onOpen` par défaut révèle dans le Finder ; l'écran Download le
    /// remplace par un passage à la bibliothèque.
    init(job: DownloadJob, manager: DownloadManager, onOpen: (() -> Void)? = nil) {
        self.init(
            job: job,
            waiting: manager.isWaiting(job),
            onTogglePause: { manager.togglePause(job.id) },
            onCancel: { manager.cancel(job.id) },
            onRetry: { manager.retry(job.id) },
            onOpen: onOpen ?? {
                if let url = job.fileURL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            },
            onDismiss: { manager.remove(job.id) }
        )
    }
}
