import Foundation

/// Configuration centrale de l'app.
enum AppConfig {

    // MARK: - Nom
    //
    // Trois formes, chacune pour une largeur d'affichage. Le nom du bundle
    // (`TBD.app`, `com.byelior.tbd`) vit dans `project.yml`.

    /// Sigle développé. Finder, Spotlight, cartouche « À propos » — partout où
    /// quelqu'un peut rencontrer l'app sans savoir ce que « TBD » veut dire.
    static let fullName = "TBD - To be downloaded"

    /// Nom courant, lu dans l'interface et le menu de l'app.
    static let displayName = "To be downloaded"

    /// Sigle seul, pour les endroits étroits : barre des menus, User-Agent,
    /// nom de dossier.
    static let shortName = "TBD"

    /// Schéma des liens entrants (`tbd://download?url=…`). Déclaré dans
    /// `CFBundleURLTypes`, émis par l'extension de partage, reçu par
    /// `AppDelegate` — d'où la constante partagée entre les deux cibles : un
    /// schéma qui diverge casserait le partage sans le moindre message.
    static let urlScheme = "tbd"

    /// Port par défaut du serveur HTTP LAN (M2).
    static let defaultPort: UInt16 = 8787

    /// Noms des binaires embarqués dans Resources/bin.
    static let ytDlpBinaryName = "yt-dlp"
    static let ffmpegBinaryName = "ffmpeg"

    // MARK: - Dossier de travail

    /// `~/Library/Application Support/TBD` : bibliothèque, vignettes, yt-dlp
    /// géré, fragments de téléchargement, bundle de certificats.
    ///
    /// `static let` plutôt que propriété calculée : la préparation du dossier
    /// (et la reprise de l'ancien) n'a lieu qu'une fois, au premier accès,
    /// quel que soit le fil d'exécution qui le demande.
    static let supportDirectory: URL = {
        let fm = FileManager.default
        let base = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                appropriateFor: nil, create: true))
            ?? fm.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        let directory = base.appendingPathComponent(shortName, isDirectory: true)

        // L'app s'est appelée « Downloader » tant qu'elle n'avait pas de nom.
        // Reprendre le dossier tel quel plutôt que repartir de zéro : sinon la
        // bibliothèque, les vignettes et le yt-dlp déjà téléchargé seraient
        // abandonnés sur place. À supprimer quand plus aucune installation
        // n'en vient.
        let legacy = base.appendingPathComponent("Downloader", isDirectory: true)
        if !fm.fileExists(atPath: directory.path), fm.fileExists(atPath: legacy.path) {
            try? fm.moveItem(at: legacy, to: directory)
        }

        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }()

    /// Version marketing du bundle (`CFBundleShortVersionString`), utilisée
    /// notamment comme User-Agent des appels réseau de l'app.
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    // MARK: - Auteur

    /// Liens affichés dans les réglages.
    enum Author {
        static let name = "Elior"
        static let website = URL(string: "https://byelior.com")!
        static let github = URL(string: "https://github.com/eliorpom-cmd")!
        static let instagram = URL(string: "https://instagram.com/elior.create")!

        /// Page de soutien. Ko-fi plutôt que Buy Me a Coffee : la plateforme ne
        /// prélève rien sur les dons en formule gratuite (BMC prend 5 %), et le
        /// versement passe par Stripe, donc directement sur un compte bancaire.
        static let support = URL(string: "https://ko-fi.com/eliorpom")!
    }

    // MARK: - Crédits

    /// Ce que l'app doit à d'autres, tel qu'affiché dans les réglages.
    ///
    /// La liste n'est pas décorative : yt-dlp et FFmpeg FONT le travail, et
    /// l'icône n'est pas de la main de l'auteur. `docs/THIRD-PARTY.md` reste la
    /// version longue (licences, obligations) — ici on donne le crédit et le
    /// lien, pas le raisonnement juridique.
    enum Credits {

        /// Auteur de l'icône de l'app. Le dessin livré (`AppIcon.icon`) est le
        /// sien ; l'app n'aurait pas de visage sans lui.
        enum Icon {
            static let author = "Saint"
            static let handle = "@app_settings"
            static let alias = "System Settings"
            static let url = URL(string: "https://x.com/app_settings")!
        }

        static let ytDlp = URL(string: "https://github.com/yt-dlp/yt-dlp")!
        static let ffmpeg = URL(string: "https://ffmpeg.org")!
        static let flyingFox = URL(string: "https://github.com/swhitty/FlyingFox")!

        /// Le détail des licences, dans le dépôt. Construit depuis
        /// `updateRepository` pour qu'un renommage du dépôt ne laisse pas un
        /// lien mort derrière lui.
        static let licenses = URL(
            string: "https://github.com/\(updateRepository)/blob/main/docs/THIRD-PARTY.md")!

        /// Licence de l'app elle-même. Elle n'est pas là pour la décoration :
        /// sous AGPL, quiconque diffuse une version modifiée — y compris en la
        /// servant sur un réseau, ce que fait justement Network Access — doit en
        /// donner la source. Le lien rend cette obligation trouvable au lieu de
        /// la laisser dormir dans un fichier du dépôt.
        static let license = URL(
            string: "https://github.com/\(updateRepository)/blob/main/LICENSE")!
    }

    // MARK: - Mises à jour de l'app

    /// Dépôt GitHub dont les releases servent de canal de mise à jour.
    static let updateRepository = "eliorpom-cmd/to-be-downloaded"

    /// Clés publiques Ed25519 (base64) qui authentifient les archives de mise à
    /// jour. Une signature valide pour **n'importe laquelle** suffit.
    ///
    /// L'app n'étant pas notarisée par Apple, cette signature est la SEULE
    /// preuve d'authenticité d'une mise à jour : sans elle, rien n'est installé.
    ///
    /// Il y en a DEUX exprès. La première sert au quotidien ; la seconde est une
    /// clé de secours rangée hors de la machine de build. Sans elle, perdre la
    /// clé courante condamnerait définitivement la mise à jour automatique des
    /// apps déjà installées — c'est le seul incident dont on ne pourrait pas se
    /// relever, puisqu'il faudrait une mise à jour pour corriger la clé.
    ///
    /// Contrepartie : deux clés peuvent autoriser une mise à jour au lieu d'une.
    /// D'où la règle — la clé de secours ne vit PAS sur la machine de build.
    ///
    /// ⚠️ Ne jamais retirer une clé déjà publiée : les versions installées ne
    /// connaissent que celles-ci.
    static let updatePublicKeys = [
        "6ylYSJBktHoAANVp3Lt/yATR1wMi1dNWVxoTtH+ix/U=",  // courante
        "Krj7bauZKnfutbN2UrwIhvcWYT/8lV5shEO3Bvlb1Qo=",  // secours (hors machine)
    ]

    /// Hôtes acceptés pour un téléchargement de mise à jour. L'URL vient d'une
    /// réponse d'API, donc on ne la suit pas aveuglément : HTTPS obligatoire et
    /// hôte connu, même si la signature Ed25519 (app) ou la somme SHA-256
    /// (yt-dlp) reste la vraie ligne de défense.
    private static let trustedUpdateHosts: Set<String> = [
        "github.com", "www.github.com",
        "api.github.com",
        "objects.githubusercontent.com",
        "release-assets.githubusercontent.com",
        "raw.githubusercontent.com",
    ]

    static func isTrustedUpdateURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased()
        else { return false }
        return trustedUpdateHosts.contains(host)
    }

    // MARK: - FFmpeg

    /// FFmpeg n'est PAS livré dans le bundle, et ce n'est pas une question de
    /// poids : le build statique qu'on embarquait était compilé
    /// `--enable-nonfree`, ce qui le rend **juridiquement non redistribuable**
    /// (son propre `ffmpeg -L` le dit). Aucune licence posée sur ce dépôt n'y
    /// change quoi que ce soit : on ne peut pas accorder de droits sur du code
    /// qu'on ne possède pas. Le télécharger au premier lancement déplace la
    /// distribution vers celui qui a le droit de la faire.
    ///
    /// Source retenue : les builds de Martin Riedl. `--enable-gpl
    /// --enable-version3` **sans** `--enable-nonfree`, donc GPLv3 et
    /// redistribuables ; arm64 natif ; signés Developer ID (vérifié à
    /// l'installation) ; et surtout des URLs « latest » stables, avec un
    /// `.sha256` publié à côté de chaque archive.
    enum FFmpegSource {
        /// Renvoie un 307 vers l'archive versionnée — d'où l'on tire la version
        /// disponible sans télécharger les 28 Mo.
        static let latestBase = "https://ffmpeg.martin-riedl.de/redirect/latest/macos/arm64/release"

        /// Les deux exécutables sont publiés séparément. yt-dlp a besoin des
        /// DEUX : ffprobe lui sert à sonder les flux avant l'assemblage.
        static let components = ["ffmpeg", "ffprobe"]

        /// Identifiant d'équipe Apple attendu sur la signature des binaires.
        /// C'est la vraie garantie de la chaîne : le SHA-256 vient du même hôte
        /// que l'archive et ne protège donc que d'un transfert tronqué, tandis
        /// qu'une signature Developer ID ne peut pas être fabriquée par
        /// quelqu'un qui prendrait le contrôle du serveur.
        static let signingTeam = "KU3N25YGLU"

        static let homepage = URL(string: "https://ffmpeg.martin-riedl.de")!

        private static let trustedHosts: Set<String> = ["ffmpeg.martin-riedl.de"]

        static func isTrustedURL(_ url: URL) -> Bool {
            guard url.scheme?.lowercased() == "https",
                  let host = url.host?.lowercased()
            else { return false }
            return trustedHosts.contains(host)
        }
    }
}
