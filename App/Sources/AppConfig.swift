import Foundation

/// Configuration centrale de l'app.
///
/// PLACEHOLDER DU NOM : change `displayName` ici pour le nom vu dans l'UI.
/// (Le nom du bundle/produit se change dans `project.yml` puis `xcodegen`.)
enum AppConfig {
    /// Nom affiché dans l'interface. Placeholder — facile à changer.
    static let displayName = "Downloader"

    /// Port par défaut du serveur HTTP LAN (M2).
    static let defaultPort: UInt16 = 8787

    /// Noms des binaires embarqués dans Resources/bin.
    static let ytDlpBinaryName = "yt-dlp"
    static let ffmpegBinaryName = "ffmpeg"

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

    // MARK: - Mises à jour de l'app

    /// Dépôt GitHub dont les releases servent de canal de mise à jour.
    static let updateRepository = "eliorpom-cmd/yt-downloader-mac"

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
}
