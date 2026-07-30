import AVFoundation
import AppKit

/// Fallback thumbnail extracted from the file itself.
///
/// The YouTube thumbnail is not always known: if metadata arrived too late, or
/// if the entry comes from an old version, the URL is nil. Rather than a gray
/// box, we take an image from the video — which has the advantage of staying
/// valid offline and surviving the disappearance of the original video.
enum PosterFrame {

    private static var directory: URL {
        AppConfig.supportDirectory
            .appendingPathComponent("thumbnails", isDirectory: true)
    }

    static func cachedURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).jpg")
    }

    /// Return the cached thumbnail, generating it if needed.
    /// `nil` for an audio file or unreadable video.
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

        // FFmpeg fallback: AVFoundation does not decode AV1 on most Macs, and
        // that is exactly what YouTube increasingly serves. The software decoder
        // we already ship does not mind.
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
        generator.appliesPreferredTrackTransform = true   // respects rotation
        generator.maximumSize = CGSize(width: 480, height: 480)
        // 10% into the video: avoids black fades and intro cards.
        let seconds = min(max(duration.seconds * 0.1, 1), 30)
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 1, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 1, preferredTimescale: 600)

        return try? await generator.image(at: time).image
    }

    /// Extract a frame at 10s with the shipped ffmpeg. Arguments as array,
    /// never shell.
    private static func extractFrameWithFFmpeg(from file: URL, to destination: URL) async -> Bool {
        // No FFmpeg installed (first launch underway): no thumbnail, and no
        // error — it will be made on the next request.
        guard let ffmpeg = try? BinaryLocator.effectiveFFmpeg() else { return false }
        let arguments = [
            "-y",
            "-ss", "10",          // before input: fast decode, no reading whole file
            "-i", file.path,
            "-frames:v", "1",
            "-vf", "scale=480:-2",
            "-q:v", "4",
            destination.path,
        ]
        guard let result = try? await ProcessRunner.run(executable: ffmpeg, arguments: arguments),
              result.exitCode == 0
        else {
            // Video shorter than 10s: retry on the very first frame.
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
