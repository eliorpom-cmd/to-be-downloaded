import Foundation

/// Photo de profil d'une chaîne YouTube.
///
/// Aucune source bon marché ne la donne : oEmbed ne renvoie que le nom de la
/// chaîne, et `yt-dlp --dump-single-json` sur une vidéo n'expose que
/// `channel_id` / `uploader_url`. La demander à yt-dlp sur l'URL de la chaîne
/// marche, mais coûte ~16 s — hors de question pour une vignette de 28 pt.
///
/// On la lit donc dans la page de la vidéo, et surtout on la MET EN CACHE par
/// chaîne : le coût (une page d'environ 1,3 Mo) est payé une fois par chaîne,
/// pas à chaque téléchargement. Un habitué de trois chaînes le paiera trois
/// fois en tout.
///
/// C'est de la décoration : en cas d'échec on retombe sur l'initiale de la
/// chaîne, et rien d'autre n'en dépend.
actor ChannelAvatars {
    static let shared = ChannelAvatars()

    /// Clé = identifiant de chaîne (`@handle` ou `UC…`), valeur = URL de l'avatar.
    private var cache: [String: String] = [:]
    private var loaded = false
    /// Résolutions en vol, pour ne pas télécharger deux fois la même page quand
    /// on lance plusieurs vidéos d'une même chaîne d'affilée.
    private var inFlight: [String: Task<String?, Never>] = [:]

    private var fileURL: URL {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support")
        return support
            .appendingPathComponent(AppConfig.displayName, isDirectory: true)
            .appendingPathComponent("channel-avatars.json")
    }

    /// Avatar de la chaîne d'une vidéo. `channelKey` sert uniquement de clé de
    /// cache ; la page téléchargée est celle de la vidéo.
    func avatarURL(channelKey: String, videoURL: String) async -> String? {
        load()
        if let cached = cache[channelKey] { return cached }
        if let running = inFlight[channelKey] { return await running.value }

        let task = Task<String?, Never> { await Self.scrape(videoURL: videoURL) }
        inFlight[channelKey] = task
        let found = await task.value
        inFlight[channelKey] = nil

        if let found {
            cache[channelKey] = found
            save()
        }
        return found
    }

    // MARK: - Extraction

    /// Première URL `yt3.ggpht.com/…=sNN-c-k-…` de la page : c'est l'avatar du
    /// propriétaire de la vidéo (vérifié en le comparant à celui que yt-dlp
    /// renvoie pour la chaîne elle-même). Le gabarit de taille est renormalisé
    /// pour obtenir une image nette sans tirer un 900 px inutile.
    private static func scrape(videoURL: String) async -> String? {
        guard let url = URL(string: videoURL) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        // Sans un User-Agent de navigateur, YouTube sert une page allégée qui
        // ne contient pas l'avatar.
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
                + "(KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let html = String(data: data, encoding: .utf8)
        else { return nil }

        let pattern = #"https://yt3\.ggpht\.com/[A-Za-z0-9_\-]+=s\d+-c-k-[A-Za-z0-9\-]*"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range, in: html)
        else { return nil }

        let raw = String(html[range])
        // `=s48-` → `=s176-` : la vignette fait 28 pt, soit 84 px en 3×.
        return raw.replacingOccurrences(
            of: #"=s\d+-"#, with: "=s176-", options: .regularExpression)
    }

    // MARK: - Persistance

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        else { return }
        cache = decoded
    }

    private func save() {
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
