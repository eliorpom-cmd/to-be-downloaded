import Foundation

/// Validation des liens acceptés. Hors acteur : appelée depuis les callbacks
/// de glisser-déposer, qui ne tournent pas sur le main actor.
enum YouTubeLink {

    /// Hôtes autorisés — l'app ne télécharge que depuis YouTube.
    static let allowedHosts: Set<String> = [
        "youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com",
        "youtu.be", "www.youtu.be",
    ]

    static func isValid(_ string: String) -> Bool {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              let host = url.host?.lowercased()
        else { return false }
        return allowedHosts.contains(host)
    }

    /// Identifiant de la vidéo, lu directement dans l'URL.
    ///
    /// Sert à afficher la vignette AVANT toute réponse réseau : interroger
    /// yt-dlp prend plusieurs secondes, et la ligne restait vide pendant ce
    /// temps alors que l'information est déjà là, dans le lien collé.
    static func videoID(from string: String) -> String? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              let host = components.host?.lowercased(),
              allowedHosts.contains(host)
        else { return nil }

        // youtu.be/<id>
        if host.hasSuffix("youtu.be") {
            return sanitize(components.path.dropFirst())
        }
        // youtube.com/watch?v=<id>
        if let v = components.queryItems?.first(where: { $0.name == "v" })?.value {
            return sanitize(v)
        }
        // /shorts/<id>, /embed/<id>, /live/<id>, /v/<id>
        let parts = components.path.split(separator: "/")
        if parts.count >= 2, ["shorts", "embed", "live", "v"].contains(String(parts[0])) {
            return sanitize(parts[1])
        }
        return nil
    }

    /// Un identifiant YouTube fait 11 caractères de l'alphabet base64-url. On
    /// vérifie plutôt que de faire confiance à l'URL : cette chaîne part
    /// ensuite dans une URL de vignette.
    private static func sanitize(_ raw: some StringProtocol) -> String? {
        let id = String(raw)
        let allowed = CharacterSet(charactersIn:
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        guard id.count == 11, id.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        return id
    }

    /// Identifiant de playlist, si le lien en désigne une.
    ///
    /// Un lien peut porter les DEUX : `watch?v=…&list=…` désigne une vidéo
    /// *dans* une playlist. C'est le cas ambigu — d'où la question posée à
    /// l'utilisateur plutôt qu'un choix fait à sa place.
    static func playlistID(from string: String) -> String? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              let host = components.host?.lowercased(),
              allowedHosts.contains(host),
              let list = components.queryItems?.first(where: { $0.name == "list" })?.value,
              !list.isEmpty
        else { return nil }
        // `RD…` = mix généré à la volée par YouTube, sans contenu stable :
        // le proposer donnerait une liste différente à chaque ouverture.
        guard !list.hasPrefix("RD") else { return nil }
        return list
    }

    /// URL canonique d'une playlist, débarrassée de la vidéo courante.
    static func playlistURL(from string: String) -> String? {
        playlistID(from: string).map { "https://www.youtube.com/playlist?list=\($0)" }
    }

    /// Vignette officielle d'une vidéo, déductible sans aucun appel réseau.
    /// `mqdefault` (320×180) suffit largement aux tailles où on l'affiche.
    static func thumbnailURL(for string: String) -> String? {
        videoID(from: string).map { "https://i.ytimg.com/vi/\($0)/mqdefault.jpg" }
    }
}
