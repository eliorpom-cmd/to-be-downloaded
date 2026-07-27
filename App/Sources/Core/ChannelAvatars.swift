import Foundation

/// Photo de profil d'une chaîne YouTube.
///
/// Aucune source bon marché ne la donne : oEmbed ne renvoie que le nom et
/// l'URL de la chaîne, et `yt-dlp --dump-single-json` sur une vidéo n'expose
/// que `channel_id` / `uploader_url`. La demander à yt-dlp sur l'URL de la
/// chaîne marche, mais coûte ~16 s — hors de question pour une vignette de
/// 28 pt.
///
/// On lit donc la PAGE DE LA CHAÎNE (~2 s), et surtout on MET EN CACHE par
/// chaîne : le coût est payé une fois par chaîne, pas à chaque
/// téléchargement. Un habitué de trois chaînes le paiera trois fois en tout.
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
            // `-v2` : les entrées de la v1 étaient lues sur la page de la vidéo
            // et désignaient souvent une chaîne recommandée, pas la bonne. Un
            // nom de fichier neuf les met au rebut sans code de migration.
            .appendingPathComponent("channel-avatars-v2.json")
    }

    /// Avatar d'une chaîne. `channelKey` sert de clé de cache, `channelURL` est
    /// la page effectivement téléchargée.
    func avatarURL(channelKey: String, channelURL: String) async -> String? {
        load()
        if let cached = cache[channelKey] { return cached }
        if let running = inFlight[channelKey] { return await running.value }

        let task = Task<String?, Never> { await Self.scrape(channelURL: channelURL) }
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

    /// `og:image` de la page de la chaîne : par définition l'avatar de CETTE
    /// chaîne, quel que soit le contenu de la page.
    ///
    /// Ne pas revenir à la page de la vidéo : ses URL `yt3` sont d'abord
    /// celles des chaînes recommandées en colonne de droite, et l'avatar du
    /// propriétaire n'y est pas repérable de façon fiable. Prendre « la
    /// première » donnait l'avatar d'une autre chaîne.
    ///
    /// Le gabarit de taille est renormalisé pour obtenir une image nette sans
    /// tirer le 900 px que sert `og:image`.
    private static func scrape(channelURL: String) async -> String? {
        guard let url = URL(string: channelURL) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        // Un User-Agent de navigateur évite les variantes allégées que YouTube
        // réserve aux clients inconnus.
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
                + "(KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent")
        // En Europe, une requête sans cookie de consentement est redirigée vers
        // `consent.youtube.com`, dont la page ne contient évidemment pas
        // l'avatar. `SOCS=CAI` est le marqueur « choix déjà fait » ; on le pose
        // à la main plutôt que de dépendre du magasin de cookies partagé, dont
        // le contenu dépend de ce que l'app a fait avant (d'où un avatar qui
        // apparaissait ou non selon les fois).
        request.httpShouldHandleCookies = false
        request.setValue("SOCS=CAI", forHTTPHeaderField: "Cookie")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let html = String(data: data, encoding: .utf8)
        else { return nil }

        // L'hôte varie (`yt3.ggpht.com`, `yt3.googleusercontent.com`) et le
        // chemin peut porter un préfixe `ytc/` : on n'ancre que sur `yt3.`.
        let pattern = #"<meta property="og:image" content="(https://yt3\.[^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html)
        else { return nil }

        let raw = String(html[range])
        // `=s900-` → `=s176-` : la vignette fait 28 pt, soit 84 px en 3×.
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
