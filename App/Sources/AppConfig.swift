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
}
