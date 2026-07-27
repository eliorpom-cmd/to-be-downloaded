import Foundation

/// Un travail de téléchargement suivi par l'UI.
struct DownloadJob: Identifiable, Sendable {
    let id: UUID
    let url: String
    let format: DownloadFormat
    var state: State
    var progress: DownloadProgress?
    var fileURL: URL?
    var errorMessage: String?
    /// Métadonnées (titre, chaîne, miniature) récupérées au démarrage.
    var metadata: MediaMetadata?
    /// Taille du fichier final (octets), renseignée à la fin.
    var fileSize: Int64?

    /// Progression GLOBALE affichée, dans [0...1].
    ///
    /// yt-dlp raisonne par flux : une vidéo se télécharge en deux passes (image
    /// puis son), chacune de 0 à 100 %, avant l'assemblage ffmpeg. Peint tel
    /// quel, l'indicateur remplissait la capsule, la vidait, la remplissait à
    /// nouveau. On projette donc chaque phase sur une portion de la barre, et on
    /// ne redescend JAMAIS : une progression qui recule est un mensonge.
    var overallProgress: Double = 0
    /// Rang du flux en cours (0 = premier fichier téléchargé).
    var streamIndex: Int = 0
    /// Fichier en cours, pour détecter le passage au flux suivant.
    var currentStreamFile: String?
    /// Début du post-traitement, pour faire avancer la barre pendant l'assemblage.
    var mergeStartedAt: Date?

    /// `id` explicite à la restauration : c'est lui qui désigne le dossier de
    /// fichiers partiels, donc le seul moyen de reprendre là où on en était.
    init(url: String, format: DownloadFormat, id: UUID = UUID()) {
        self.id = id
        self.url = url
        self.format = format
        self.state = .queued
    }

    enum State: Sendable, Equatable {
        case queued
        case downloading
        /// Process yt-dlp suspendu (SIGSTOP). Reprend là où il en était.
        case paused
        /// Téléchargement fini, ffmpeg assemble les flux (ou extrait l'audio).
        case merging
        case completed
        case failed
        case cancelled

        /// Le job occupe encore le moteur (badge Dock, section « Downloading »).
        var isActive: Bool {
            switch self {
            case .queued, .downloading, .paused, .merging: return true
            case .completed, .failed, .cancelled: return false
            }
        }

        /// Une barre de progression a du sens dans cet état.
        var showsProgress: Bool {
            switch self {
            case .downloading, .paused, .merging: return true
            default: return false
            }
        }
    }

    /// Fraction à peindre dans la capsule : une seule barre, du début du
    /// téléchargement à la fin de l'assemblage.
    var progressFraction: Double? {
        switch state {
        case .completed: return 1
        case .downloading, .paused, .merging: return overallProgress
        case .queued: return 0
        default: return nil
        }
    }

    /// Portion de la barre attribuée à une phase.
    ///
    /// Les poids reflètent le temps réellement passé : la piste vidéo domine,
    /// l'audio est court, l'assemblage plus court encore. Une vidéo passe donc
    /// par 0→58 % (image), 58→88 % (son), 88→100 % (assemblage) ; un MP3 n'a
    /// qu'un flux, puis l'extraction.
    static func phaseSpan(streamIndex: Int, kind: MediaKind) -> ClosedRange<Double> {
        switch kind {
        case .audio:
            return streamIndex == 0 ? 0...0.85 : 0.85...0.92
        case .video:
            switch streamIndex {
            case 0:  return 0...0.58
            case 1:  return 0.58...0.88
            default: return 0.88...0.92
            }
        }
    }

    /// Là où s'arrête le téléchargement et où commence le post-traitement.
    var postProcessingFloor: Double {
        switch format.kind {
        case .audio: return 0.85
        case .video: return 0.88
        }
    }

    /// Nom de fichier final (si terminé).
    var fileName: String? { fileURL?.lastPathComponent }

    /// Meilleur libellé à afficher : titre connu > nom de fichier > URL brute.
    var displayTitle: String {
        if let t = metadata?.title, !t.isEmpty { return t }
        return fileName ?? url
    }

    /// Vignette à peindre. Déduite de l'identifiant YouTube, donc disponible
    /// dès la création du job — sans attendre la moindre réponse réseau.
    var thumbnailURL: String? {
        YouTubeLink.thumbnailURL(for: url) ?? metadata?.thumbnailURL
    }
}
