import Foundation
import FlyingFox

/// Démarre/arrête le serveur HTTP LAN et expose son état à l'UI.
/// Partage le même DownloadManager que l'UI native (moteur unique).
@MainActor
final class ServerController: ObservableObject {

    @Published private(set) var isRunning = false
    @Published private(set) var url: String?
    @Published private(set) var lastError: String?
    /// Dernier appel reçu d'un appareil du réseau (poll /api/jobs). Sert à
    /// afficher « appareil connecté » tant qu'un client garde la page ouverte.
    @Published private(set) var lastClientPing: Date?

    private(set) var port: UInt16
    private let downloads: DownloadManager
    private var server: HTTPServer?
    private var task: Task<Void, Never>?

    init(downloads: DownloadManager) {
        self.downloads = downloads
        self.port = AppSettings.shared.port
    }

    func start() {
        guard server == nil else { return }
        lastError = nil
        port = AppSettings.shared.port

        let server = HTTPServer(address: .inet(port: port))
        self.server = server

        let ip = NetworkInfo.localIPAddress() ?? "127.0.0.1"
        url = "http://\(ip):\(port)"
        isRunning = true

        // Icône PNG pré-rendue (PWA / apple-touch-icon), générée hors des
        // handlers (qui tournent hors du thread principal).
        let iconData = AppIcon.png(size: 512)
        // Variante serrée pour l'onglet du navigateur : voir `AppIcon.favicon`.
        let faviconData = AppIcon.favicon(size: 64)

        task = Task { [weak self] in
            await self?.configureRoutes(on: server, iconData: iconData, faviconData: faviconData)
            do {
                try await server.run()
            } catch {
                // Arrêt volontaire (task annulée) : ce n'est pas une erreur.
                if Task.isCancelled { return }
                await MainActor.run {
                    self?.lastError = error.localizedDescription
                    self?.isRunning = false
                    self?.server = nil
                    self?.url = nil
                }
            }
        }
    }

    func stop() {
        task?.cancel()
        let server = self.server
        Task { await server?.stop() }
        self.server = nil
        task = nil
        isRunning = false
        url = nil
        lastClientPing = nil
    }

    /// Redémarre le serveur (ex. après un changement de port dans les Réglages).
    func restart() {
        stop()
        start()
    }

    private func noteClientActivity() { lastClientPing = Date() }

    // MARK: - Routes

    private func configureRoutes(
        on server: HTTPServer, iconData: Data?, faviconData: Data?
    ) async {
        let downloads = self.downloads
        let appName = AppConfig.displayName

        // Page web
        await server.appendRoute("GET /") { _ in
            // Lu à chaque requête, et non capturé au démarrage : changer le
            // format audio dans l'app doit se voir au rafraîchissement suivant.
            let audioBitrateSelectable = await MainActor.run {
                AppSettings.shared.audioFormat.usesBitrate
            }
            let html = WebUI.indexHTML(
                appName: appName, audioBitrateSelectable: audioBitrateSelectable)
            return HTTPResponse(statusCode: .ok,
                                headers: [.contentType: "text/html; charset=utf-8"],
                                body: Data(html.utf8))
        }

        // Manifest PWA (« Ajouter à l'écran d'accueil »).
        await server.appendRoute("GET /manifest.webmanifest") { _ in
            HTTPResponse(statusCode: .ok,
                         headers: [.contentType: "application/manifest+json"],
                         body: Data(WebUI.manifestJSON(appName: appName).utf8))
        }

        // Icône d'écran d'accueil (PWA + apple-touch-icon).
        await server.appendRoute("GET /icon-512.png") { _ in
            guard let iconData else {
                return HTTPResponse(statusCode: .notFound, body: Data())
            }
            return HTTPResponse(statusCode: .ok,
                                headers: [.contentType: "image/png"],
                                body: iconData)
        }

        // Icône d'onglet.
        await server.appendRoute("GET /favicon.png") { _ in
            guard let faviconData else {
                return HTTPResponse(statusCode: .notFound, body: Data())
            }
            return HTTPResponse(statusCode: .ok,
                                headers: [.contentType: "image/png"],
                                body: faviconData)
        }

        // Liste des jobs (chaque appel = un appareil actif sur le réseau).
        await server.appendRoute("GET /api/jobs") { [weak self] _ in
            await self?.noteClientActivity()
            let jobs = await downloads.snapshot()
            let data = (try? JSONEncoder().encode(jobs)) ?? Data("[]".utf8)
            return HTTPResponse(statusCode: .ok,
                                headers: [.contentType: "application/json"],
                                body: data)
        }

        // Aperçu des métadonnées (titre/chaîne/durée/miniature), sans téléchargement.
        await server.appendRoute("GET /api/metadata") { request in
            let url = request.query["url"]?.trimmingCharacters(in: .whitespaces) ?? ""
            guard !url.isEmpty, let meta = await downloads.fetchMetadata(urlString: url) else {
                return HTTPResponse(statusCode: .notFound,
                                    headers: [.contentType: "application/json"],
                                    body: Data(#"{"error":"unavailable"}"#.utf8))
            }
            let data = (try? JSONEncoder().encode(MetadataDTO(meta))) ?? Data("{}".utf8)
            return HTTPResponse(statusCode: .ok,
                                headers: [.contentType: "application/json"],
                                body: data)
        }

        // Nouveau téléchargement
        await server.appendRoute("POST /api/download") { request in
            guard let body = try? await request.bodyData,
                  let dto = try? JSONDecoder().decode(DownloadRequestDTO.self, from: body),
                  !dto.url.trimmingCharacters(in: .whitespaces).isEmpty else {
                return HTTPResponse(statusCode: .badRequest,
                                    headers: [.contentType: "application/json"],
                                    body: Data(#"{"error":"invalid request"}"#.utf8))
            }
            // Le conteneur audio et les sous-titres suivent les réglages de
            // l'app : la page web ne les expose pas, elle ne doit pas décider
            // à leur place.
            let defaults = await MainActor.run { AppSettings.shared.currentDefaultFormat }
            let id = await downloads.startDownload(
                urlString: dto.url, format: dto.toFormat(defaults: defaults))
            let payload = ["id": id?.uuidString ?? ""]
            let data = (try? JSONEncoder().encode(payload)) ?? Data("{}".utf8)
            return HTTPResponse(statusCode: .ok,
                                headers: [.contentType: "application/json"],
                                body: data)
        }

        // Annuler un téléchargement
        await server.appendRoute("POST /api/cancel/:id") { (_: HTTPRequest, id: String) in
            if let uuid = UUID(uuidString: id) { await downloads.cancel(uuid) }
            return HTTPResponse(statusCode: .ok,
                                headers: [.contentType: "application/json"],
                                body: Data("{}".utf8))
        }

        // Effacer les téléchargements terminés/échoués/annulés
        await server.appendRoute("POST /api/clear") { _ in
            await downloads.removeCompleted()
            return HTTPResponse(statusCode: .ok,
                                headers: [.contentType: "application/json"],
                                body: Data("{}".utf8))
        }

        // Récupération du fichier fini (streamé, pas chargé en RAM)
        await server.appendRoute("GET /api/file/:id") { (_: HTTPRequest, id: String) in
            guard let uuid = UUID(uuidString: id),
                  let fileURL = await downloads.fileURL(forJobID: uuid),
                  let body = try? HTTPBodySequence(file: fileURL) else {
                return HTTPResponse(statusCode: .notFound, body: Data("File unavailable".utf8))
            }
            let name = fileURL.lastPathComponent
            let encoded = name.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? name
            return HTTPResponse(
                statusCode: .ok,
                headers: [
                    .contentType: "application/octet-stream",
                    .contentDisposition: "attachment; filename=\"\(name)\"; filename*=UTF-8''\(encoded)",
                ],
                body: body
            )
        }
    }
}
