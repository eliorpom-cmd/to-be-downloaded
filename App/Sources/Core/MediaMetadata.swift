import Foundation

/// Métadonnées d'un média, extraites SANS téléchargement via
/// `yt-dlp --dump-single-json --skip-download`. Sert à l'aperçu (avant le
/// téléchargement) côté UI native et web.
struct MediaMetadata: Codable, Sendable, Equatable {
    var title: String
    var channel: String?
    /// Durée en secondes.
    var duration: Double?
    /// URL absolue de la miniature de la vidéo (chargée par le client).
    var thumbnailURL: String?
    /// Page de la chaîne, quand on la connaît (`https://youtube.com/@handle`).
    var channelURL: String?
    /// Photo de profil de la chaîne, résolue à part (cf. `ChannelAvatars`).
    var channelAvatarURL: String?

    /// Poids estimé du fichier final par hauteur vidéo (clé 0 = « Max »),
    /// piste audio comprise. Calculé une fois à partir de la liste des formats.
    var videoBytes: [Int: Int64]?
    /// Poids de la meilleure piste audio seule.
    var audioBytes: Int64?

    /// Décode la sortie `--dump-single-json` de yt-dlp en ne gardant que les
    /// champs utiles. La charge complète est énorme : on ignore tout le reste.
    static func decode(from data: Data) -> MediaMetadata? {
        struct RawFormat: Decodable {
            let height: Int?
            let vcodec: String?
            let acodec: String?
            let abr: Double?
            let filesize: Int64?
            let filesize_approx: Int64?

            var bytes: Int64? { filesize ?? filesize_approx }
            var isVideoOnly: Bool { (acodec ?? "none") == "none" && (vcodec ?? "none") != "none" }
            var isAudioOnly: Bool { (vcodec ?? "none") == "none" && (acodec ?? "none") != "none" }
            var isH264: Bool { (vcodec ?? "").hasPrefix("avc1") }
        }
        struct Raw: Decodable {
            let title: String?
            let uploader: String?
            let channel: String?
            let duration: Double?
            let thumbnail: String?
            let formats: [RawFormat]?
        }
        guard let raw = try? JSONDecoder().decode(Raw.self, from: data) else { return nil }
        let title = raw.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let title, !title.isEmpty else { return nil }

        var metadata = MediaMetadata(
            title: title,
            channel: raw.channel ?? raw.uploader,
            duration: raw.duration,
            thumbnailURL: raw.thumbnail
        )

        if let formats = raw.formats {
            let audio = formats.filter { $0.isAudioOnly && $0.bytes != nil }
            // La piste retenue au téléchargement est la meilleure disponible :
            // on estime avec la même.
            let bestAudio = audio.max { ($0.abr ?? 0) < ($1.abr ?? 0) }
            metadata.audioBytes = bestAudio?.bytes

            let video = formats.filter { $0.isVideoOnly && $0.height != nil && $0.bytes != nil }
            var sizes: [Int: Int64] = [:]
            for target in VideoQuality.allCases {
                let candidates = target == .max
                    ? video
                    : video.filter { $0.height! <= target.rawValue }
                // Même ordre de préférence que le sélecteur `-f` : la définition
                // d'abord, H.264 à définition égale.
                guard let best = candidates.max(by: { a, b in
                    a.height! != b.height! ? a.height! < b.height!
                        : (a.isH264 ? 0 : 1) > (b.isH264 ? 0 : 1)
                }) else { continue }
                sizes[target.rawValue] = (best.bytes ?? 0) + (bestAudio?.bytes ?? 0)
            }
            metadata.videoBytes = sizes.isEmpty ? nil : sizes
        }

        return metadata
    }

    /// Poids attendu du fichier produit pour un format donné, `nil` si les
    /// formats n'ont pas encore été lus. C'est une ESTIMATION : yt-dlp lui-même
    /// ne connaît qu'approximativement la taille des flux fragmentés.
    func estimatedBytes(for format: DownloadFormat) -> Int64? {
        switch format.kind {
        case .video:
            return videoBytes?[format.videoQuality.rawValue]
        case .audio:
            switch format.audioFormat {
            case .m4a:
                return audioBytes
            case .mp3:
                // Le MP3 est ré-encodé à débit constant : sa taille se déduit
                // de la durée, pas de celle de la source.
                guard let duration, duration > 0 else { return nil }
                return Int64(duration * Double(format.audioBitrate.rawValue) * 1000 / 8)
            }
        }
    }

    /// Titre et chaîne par l'endpoint oEmbed public de YouTube.
    ///
    /// `yt-dlp --dump-single-json` lance un interpréteur Python et extrait la
    /// page entière : plusieurs secondes, pendant lesquelles la ligne n'affiche
    /// ni titre ni chaîne. oEmbed répond en une requête JSON de quelques
    /// centaines de millisecondes. On s'en sert pour peupler l'affichage tout
    /// de suite, yt-dlp complétant ensuite (durée, formats).
    ///
    /// Aucune conséquence en cas d'échec : c'est un raccourci, pas une source.
    static func oEmbed(for url: String) async -> MediaMetadata? {
        guard YouTubeLink.isValid(url),
              var components = URLComponents(string: "https://www.youtube.com/oembed")
        else { return nil }
        components.queryItems = [
            URLQueryItem(name: "url", value: url),
            URLQueryItem(name: "format", value: "json"),
        ]
        guard let endpoint = components.url else { return nil }

        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 5
        request.setValue("\(AppConfig.shortName)/\(AppConfig.version)",
                         forHTTPHeaderField: "User-Agent")

        struct Payload: Decodable {
            let title: String?
            let author_name: String?
            let author_url: String?
            let thumbnail_url: String?
        }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let payload = try? JSONDecoder().decode(Payload.self, from: data),
              let title = payload.title?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty
        else { return nil }

        return MediaMetadata(
            title: title,
            channel: payload.author_name,
            duration: nil,
            thumbnailURL: payload.thumbnail_url,
            channelURL: payload.author_url
        )
    }

    /// Clé de cache d'une chaîne : le `@handle` ou l'identifiant `UC…` extrait
    /// de l'URL de la chaîne. Stable, contrairement au nom affiché.
    var channelKey: String? {
        guard let channelURL, let url = URL(string: channelURL) else { return nil }
        let last = url.lastPathComponent
        return last.isEmpty ? nil : last
    }
}
