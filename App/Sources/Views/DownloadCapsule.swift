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
    let onTogglePause: () -> Void
    let onCancel: () -> Void
    let onRetry: () -> Void
    let onReveal: () -> Void

    @State private var hovering = false

    private var isFailed: Bool { job.state == .failed }

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
        .onTapGesture {
            if job.state == .completed { onReveal() }
        }
        .contextMenu { menu }
        .help(helpText)
    }

    private var helpText: String {
        switch job.state {
        case .failed:    return job.errorMessage ?? "Failed"
        case .completed: return "Show in Finder — \(job.displayTitle)"
        default:         return job.displayTitle
        }
    }

    // MARK: - Meta

    /// Place réservée à la meta pendant qu'elle bouge. Les états figés
    /// (terminé, annulé) n'en ont pas besoin et laissent la place au titre.
    private var metaWidth: CGFloat? {
        switch job.state {
        case .queued, .downloading, .paused, .merging: return 92
        case .completed, .failed, .cancelled: return nil
        }
    }

    private var metaText: String {
        switch job.state {
        case .queued:
            return "Starting…"
        case .downloading:
            // Le pourcentage suit la barre unique, pas le flux en cours : les
            // deux doivent raconter la même histoire.
            var parts = ["\(Int(job.overallProgress * 100))%"]
            let eta = Format.eta(job.progress?.eta)
            let speed = Format.speed(job.progress?.speed)
            if !eta.isEmpty { parts.append(eta) } else if !speed.isEmpty { parts.append(speed) }
            return parts.joined(separator: " · ")
        case .paused:
            return "Paused · \(Int(job.overallProgress * 100))%"
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
        case .queued, .downloading:
            // Au survol on propose d'annuler, sinon de mettre en pause.
            if hovering {
                IconButton(symbol: "xmark.circle.fill", size: 15, help: "Cancel", action: onCancel)
            } else {
                IconButton(symbol: "pause.circle.fill", size: 15, help: "Pause", action: onTogglePause)
            }
        case .paused:
            if hovering {
                IconButton(symbol: "xmark.circle.fill", size: 15, help: "Cancel", action: onCancel)
            } else {
                IconButton(symbol: "play.circle.fill", size: 15, help: "Resume", action: onTogglePause)
            }
        case .merging:
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.7)
                .frame(width: 22, height: 22)
        case .completed:
            IconButton(symbol: "checkmark.circle.fill", size: 15, help: "Show in Finder", action: onReveal)
        case .failed, .cancelled:
            IconButton(symbol: "arrow.clockwise", size: 13, help: "Try again", action: onRetry)
        }
    }

    // MARK: - Menu contextuel

    @ViewBuilder
    private var menu: some View {
        if job.state == .completed, let url = job.fileURL {
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
    init(job: DownloadJob, manager: DownloadManager) {
        self.init(
            job: job,
            onTogglePause: { manager.togglePause(job.id) },
            onCancel: { manager.cancel(job.id) },
            onRetry: { manager.retry(job.id) },
            onReveal: {
                if let url = job.fileURL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            }
        )
    }
}
