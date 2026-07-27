import AppKit

/// Ouverture des fichiers produits.
enum FileOpener {

    /// Lance le fichier dans le lecteur par défaut, et à défaut le montre dans
    /// le Finder.
    ///
    /// `NSWorkspace.open` échoue silencieusement quand l'application associée
    /// refuse de démarrer (fraîchement installée et encore en quarantaine, par
    /// exemple) : macOS affiche alors « Élément non ouvert » et l'utilisateur
    /// se retrouve sans rien. Révéler le fichier laisse au moins une porte de
    /// sortie.
    static func play(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            reveal(url)
            return
        }
        if !NSWorkspace.shared.open(url) {
            reveal(url)
        }
    }

    static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
