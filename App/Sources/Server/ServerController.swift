// TBD — To be downloaded. Copyright (C) 2026 Elior Pommier.
// Licensed under the GNU AGPL v3 or later. See LICENSE and NOTICE.
import Foundation
import FlyingFox

/// Starts/stops the LAN HTTP server and exposes its state to the UI.
/// Shares the same DownloadManager as the native UI (single engine).
@MainActor
final class ServerController: ObservableObject {

    @Published private(set) var isRunning = false
    @Published private(set) var url: String?
    @Published private(set) var lastError: String?
    /// Last call from a network device (poll /api/jobs). Used to display
    /// "device connected" as long as a client keeps the page open.
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

        // Pre-rendered PNG icon (PWA / apple-touch-icon), generated outside of
        // handlers (which run off the main thread).
        let iconData = AppIcon.png(size: 512)
        // Tight variant for the browser tab: see `AppIcon.favicon`.
        let faviconData = AppIcon.favicon(size: 64)

        task = Task { [weak self] in
            await self?.configureRoutes(on: server, iconData: iconData, faviconData: faviconData)
            do {
                try await server.run()
            } catch {
                // Voluntary stop (task cancelled): not an error.
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

    /// Restarts the server (e.g. after a port change in Settings).
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
        let shortName = AppConfig.shortName

        // Web page
        await server.appendRoute("GET /") { _ in
            // Read on each request, not captured at startup: changing the audio
            // format in the app must be visible on the next refresh.
            let audioBitrateSelectable = await MainActor.run {
                AppSettings.shared.audioFormat.usesBitrate
            }
            let html = WebUI.indexHTML(
                appName: appName, shortName: shortName,
                audioBitrateSelectable: audioBitrateSelectable)
            return HTTPResponse(statusCode: .ok,
                                headers: [.contentType: "text/html; charset=utf-8"] as HTTPHeaders,
                                body: Data(html.utf8))
        }

        // PWA manifest ("Add to Home Screen").
        await server.appendRoute("GET /manifest.webmanifest") { _ in
            HTTPResponse(statusCode: .ok,
                         headers: [.contentType: "application/manifest+json"] as HTTPHeaders,
                         body: Data(WebUI.manifestJSON(appName: appName,
                                                       shortName: shortName).utf8))
        }

        // Home screen icon (PWA + apple-touch-icon).
        await server.appendRoute("GET /icon-512.png") { _ in
            guard let iconData else {
                return HTTPResponse(statusCode: .notFound, body: Data())
            }
            return HTTPResponse(statusCode: .ok,
                                headers: [.contentType: "image/png"] as HTTPHeaders,
                                body: iconData)
        }

        // Tab icon.
        await server.appendRoute("GET /favicon.png") { _ in
            guard let faviconData else {
                return HTTPResponse(statusCode: .notFound, body: Data())
            }
            return HTTPResponse(statusCode: .ok,
                                headers: [.contentType: "image/png"] as HTTPHeaders,
                                body: faviconData)
        }

        // Job list (each call = one active device on the network).
        await server.appendRoute("GET /api/jobs") { [weak self] _ in
            await self?.noteClientActivity()
            let jobs = await downloads.snapshot()
            let data = (try? JSONEncoder().encode(jobs)) ?? Data("[]".utf8)
            return HTTPResponse(statusCode: .ok,
                                headers: [.contentType: "application/json"] as HTTPHeaders,
                                body: data)
        }

        // Metadata preview (title/channel/duration/thumbnail), no download.
        await server.appendRoute("GET /api/metadata") { request in
            let url = request.query["url"]?.trimmingCharacters(in: .whitespaces) ?? ""
            guard !url.isEmpty, let meta = await downloads.fetchMetadata(urlString: url) else {
                return HTTPResponse(statusCode: .notFound,
                                    headers: [.contentType: "application/json"] as HTTPHeaders,
                                    body: Data(#"{"error":"unavailable"}"#.utf8))
            }
            let data = (try? JSONEncoder().encode(MetadataDTO(meta))) ?? Data("{}".utf8)
            return HTTPResponse(statusCode: .ok,
                                headers: [.contentType: "application/json"] as HTTPHeaders,
                                body: data)
        }

        // New download
        await server.appendRoute("POST /api/download") { request in
            guard let body = try? await request.bodyData,
                  let dto = try? JSONDecoder().decode(DownloadRequestDTO.self, from: body),
                  !dto.url.trimmingCharacters(in: .whitespaces).isEmpty else {
                return HTTPResponse(statusCode: .badRequest,
                                    headers: [.contentType: "application/json"] as HTTPHeaders,
                                    body: Data(#"{"error":"invalid request"}"#.utf8))
            }
            // Audio container and subtitles follow the app's settings:
            // the web page does not expose them, it must not decide for them.
            let defaults = await MainActor.run { AppSettings.shared.currentDefaultFormat }
            let id = await downloads.startDownload(
                urlString: dto.url, format: dto.toFormat(defaults: defaults))
            let payload = ["id": id?.uuidString ?? ""]
            let data = (try? JSONEncoder().encode(payload)) ?? Data("{}".utf8)
            return HTTPResponse(statusCode: .ok,
                                headers: [.contentType: "application/json"] as HTTPHeaders,
                                body: data)
        }

        // Cancel a download
        await server.appendRoute("POST /api/cancel/:id") { (_: HTTPRequest, id: String) in
            if let uuid = UUID(uuidString: id) { await downloads.cancel(uuid) }
            return HTTPResponse(statusCode: .ok,
                                headers: [.contentType: "application/json"] as HTTPHeaders,
                                body: Data("{}".utf8))
        }

        // Clear completed/failed/cancelled downloads
        await server.appendRoute("POST /api/clear") { _ in
            await downloads.removeCompleted()
            return HTTPResponse(statusCode: .ok,
                                headers: [.contentType: "application/json"] as HTTPHeaders,
                                body: Data("{}".utf8))
        }

        // Fetch the finished file (streamed, not loaded in RAM)
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
                ] as HTTPHeaders,
                body: body
            )
        }
    }
}
