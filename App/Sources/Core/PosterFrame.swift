import AVFoundation
import AppKit

/// Vignette de repli extraite du fichier lui-même.
///
/// La miniature YouTube n'est pas toujours connue : si les métadonnées sont
/// arrivées trop tard, ou si l'entrée vient d'une ancienne version, l'URL est
/// nulle. Plutôt qu'une case grise, on prend une image dans la vidéo — ce qui a
/// l'avantage de rester valable hors ligne et de survivre à la disparition de
/// la vidéo d'origine.
enum PosterFrame {

    private static var directory: URL {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support")
        return support
            .appendingPathComponent(AppConfig.displayName, isDirectory: true)
            .appendingPathComponent("thumbnails", isDirectory: true)
    }

    static func cachedURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).jpg")
    }

    /// Renvoie la vignette en cache, en la produisant au besoin.
    /// `nil` pour un fichier audio ou une vidéo illisible.
    static func image(for id: UUID, file: URL) async -> NSImage? {
        let cached = cachedURL(for: id)
        if let image = NSImage(contentsOf: cached) { return image }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        if let generated = await extractFrame(from: file) {
            if let data = jpegData(from: generated) {
                try? data.write(to: cached, options: .atomic)
            }
            return NSImage(cgImage: generated, size: .zero)
        }

        // Repli ffmpeg : AVFoundation ne décode pas l'AV1 sur la plupart des
        // Mac, et c'est justement ce que YouTube sert de plus en plus. Le
        // décodeur logiciel qu'on embarque déjà, lui, ne s'en soucie pas.
        if await extractFrameWithFFmpeg(from: file, to: cached) {
            return NSImage(contentsOf: cached)
        }
        return nil
    }

    static func removeCache(for id: UUID) {
        try? FileManager.default.removeItem(at: cachedURL(for: id))
    }

    private static func extractFrame(from file: URL) async -> CGImage? {
        let asset = AVURLAsset(url: file)
        guard let duration = try? await asset.load(.duration),
              duration.seconds.isFinite, duration.seconds > 0,
              let tracks = try? await asset.loadTracks(withMediaType: .video),
              !tracks.isEmpty
        else { return nil }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true   // respecte la rotation
        generator.maximumSize = CGSize(width: 480, height: 480)
        // 10 % du film : évite les fondus au noir et les cartons de début.
        let seconds = min(max(duration.seconds * 0.1, 1), 30)
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 1, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 1, preferredTimescale: 600)

        return try? await generator.image(at: time).image
    }

    /// Extrait une image à 10 s avec le ffmpeg embarqué. Arguments en tableau,
    /// jamais de shell.
    private static func extractFrameWithFFmpeg(from file: URL, to destination: URL) async -> Bool {
        guard let ffmpeg = try? BinaryLocator.url(for: AppConfig.ffmpegBinaryName) else { return false }
        let arguments = [
            "-y",
            "-ss", "10",          // avant l'entrée : décodage rapide, sans lire tout le fichier
            "-i", file.path,
            "-frames:v", "1",
            "-vf", "scale=480:-2",
            "-q:v", "4",
            destination.path,
        ]
        guard let result = try? await ProcessRunner.run(executable: ffmpeg, arguments: arguments),
              result.exitCode == 0
        else {
            // Vidéo plus courte que 10 s : on retente sur la toute première image.
            guard let retry = try? await ProcessRunner.run(
                executable: ffmpeg,
                arguments: ["-y", "-i", file.path, "-frames:v", "1",
                            "-vf", "scale=480:-2", "-q:v", "4", destination.path])
            else { return false }
            return retry.exitCode == 0
        }
        return true
    }

    private static func jpegData(from image: CGImage) -> Data? {
        let rep = NSBitmapImageRep(cgImage: image)
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
    }
}
