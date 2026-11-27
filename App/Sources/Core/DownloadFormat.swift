// TBD — To Be Downloaded. Copyright (C) 2026 Elior Pommier.
// Licensed under the GNU AGPL v3 or later. See LICENSE and NOTICE.
import Foundation

/// Media type to produce.
enum MediaKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case video
    case audio
    var id: String { rawValue }

    /// The container is not in the label: it's set separately
    /// (`VideoContainer`, `AudioFormat`).
    var label: String {
        switch self {
        case .video: return "Video"
        case .audio: return "Audio"
        }
    }
}

/// Video quality (max height in pixels; `max` = best available).
enum VideoQuality: Int, CaseIterable, Sendable, Identifiable {
    case p360 = 360
    case p480 = 480
    case p720 = 720
    case p1080 = 1080
    case max = 0

    var id: Int { rawValue }
    var label: String { self == .max ? "Max" : "\(rawValue)p" }
}

/// Which subtitle track to embed or save, when the video has one.
///
/// Deliberately short. yt-dlp accepts every language YouTube has, but a list
/// of two hundred entries is a worse answer than a list of nine: the ones
/// worth naming are the ones people actually read, and "System language"
/// covers everyone else without asking them anything. "Original language"
/// comes first and is the default: what the people in the video actually
/// say, rather than a translation of it.
enum SubtitleLanguage: String, CaseIterable, Sendable, Identifiable, Codable {
    case original
    case system
    case en, fr, es, de, it, pt, ja, ko, zh

    var id: String { rawValue }

    var label: String {
        switch self {
        case .original: return "Original language"
        case .system: return "System language"
        case .en: return "English"
        case .fr: return "French"
        case .es: return "Spanish"
        case .de: return "German"
        case .it: return "Italian"
        case .pt: return "Portuguese"
        case .ja: return "Japanese"
        case .ko: return "Korean"
        case .zh: return "Chinese"
        }
    }

    /// Codes handed to `--sub-langs`, in preference order.
    ///
    /// English trails every other choice: it is the one language nearly every
    /// channel captions, so it is the fallback that stops "subtitles on"
    /// meaning "no subtitles" on a video that simply has none in yours.
    ///
    /// For `.original`, the video's language is not known here: these are the
    /// "System language" codes, the fallback `resolvedCodes(originalLanguage:autoCaptions:)` uses.
    var codes: [String] {
        switch self {
        case .original, .system:
            let current = Locale.current.language.languageCode?.identifier ?? "en"
            return current == "en" ? ["en"] : [current, "en"]
        case .en:
            return ["en"]
        default:
            return [rawValue, "en"]
        }
    }

    /// Codes handed to `--sub-langs` for a given video.
    ///
    /// `.original` asks for the language the video was made in, and only
    /// that one: no English fallback, since a translation is exactly what it
    /// is there to avoid. With automatic captions allowed, YouTube's
    /// original-language transcription is asked for too: yt-dlp lists it as
    /// `<language>-orig`, apart from the machine translations into that same
    /// language. When the video's language is unknown, the "System language"
    /// codes.
    func resolvedCodes(originalLanguage: String?, autoCaptions: Bool) -> [String] {
        guard self == .original,
              let language = originalLanguage?.trimmingCharacters(in: .whitespacesAndNewlines),
              !language.isEmpty
        else { return codes }
        return autoCaptions ? [language, "\(language)-orig"] : [language]
    }
}

/// MP3 audio bitrate.
enum AudioBitrate: Int, CaseIterable, Sendable, Identifiable {
    case k128 = 128
    case k192 = 192
    case k320 = 320

    var id: Int { rawValue }
    var label: String { "\(rawValue) kbps" }
}

/// Container a video is written in.
///
/// Every choice here is a REMUX: the streams YouTube sends are put in another
/// box, instantly and without loss (`--merge-output-format`). Nothing is
/// re-encoded, so the choice also decides which streams can be picked, since
/// not every codec fits every container:
/// - MP4: H.264 + AAC up to 1080p, VP9/AV1 above (Max). The default, and the
///   promise that the file opens in QuickTime, Photos and on an iPhone.
/// - MOV: H.264 + AAC only, so at most 1080p. Apple's own container.
/// - MKV: holds anything. Same streams as MP4, for people whose player or
///   editor wants MKV.
/// - WebM: VP9/AV1 + Opus only, YouTube's own streams, untouched.
/// AVI and FLV are left out: neither can hold the codecs YouTube serves today.
enum VideoContainer: String, CaseIterable, Sendable, Identifiable, Codable {
    case mp4, mov, mkv, webm

    var id: String { rawValue }

    var label: String { rawValue.uppercased() }

    var detail: String {
        switch self {
        case .mp4:  return "Opens everywhere, including QuickTime and iPhone."
        case .mov:  return "H.264 only, so up to 1080p. Opens everywhere on Apple devices."
        case .mkv:  return "No re-encoding. QuickTime can't open MKV: use VLC or IINA."
        case .webm: return "YouTube's own VP9 and Opus streams, no re-encoding. "
                         + "QuickTime can't open WebM: use VLC, IINA or a browser."
        }
    }

    /// Does QuickTime open every file this container can produce at the
    /// given quality?
    func playsInQuickTime(at quality: VideoQuality) -> Bool {
        switch self {
        case .mov:  return true
        case .mp4:  return quality != .max
        case .mkv, .webm: return false
        }
    }

    /// Subtitles can be embedded (yt-dlp embeds in MP4, MKV and WebM only).
    var embedsSubtitles: Bool { self != .mov }

    /// A part of a video is re-encoded to H.264 for an exact cut (see
    /// `DownloadEngine.clipEncoderArguments`). WebM cannot hold H.264, so a
    /// WebM clip is written as MP4, and the interface says so.
    func forClip() -> VideoContainer { self == .webm ? .mp4 : self }
}

/// Output audio format.
///
/// YouTube serves AAC (M4A) and Opus. Keeping either as is avoids a second
/// encode, which costs time and quality. The others are re-encoded, and say
/// so: MP3 for old hardware, FLAC and WAV for editors that want them (they
/// are larger, not better: the source is already compressed).
enum AudioFormat: String, CaseIterable, Sendable, Identifiable, Codable {
    case m4a
    case opus
    case mp3
    case flac
    case wav

    var id: String { rawValue }

    var label: String { rawValue.uppercased() }

    var detail: String {
        switch self {
        case .m4a:  return "Keeps the original audio. No re-encoding, better quality."
        case .opus: return "Keeps YouTube's Opus audio. No re-encoding. Not every player reads it."
        case .mp3:  return "Re-encoded, lower quality"
        case .flac: return "Re-encoded, lossless from here. Larger, not better than the source."
        case .wav:  return "Re-encoded, uncompressed. Very large."
        }
    }

    /// Bitrate is adjustable only for a lossy re-encode.
    var usesBitrate: Bool { self == .mp3 }

    /// The source track is kept as is.
    var keepsOriginal: Bool { self == .m4a || self == .opus }
}

/// Complete download specification.
struct DownloadFormat: Sendable, Equatable, Codable {
    var kind: MediaKind
    var videoQuality: VideoQuality = .p1080
    var audioBitrate: AudioBitrate = .k192
    var audioFormat: AudioFormat = .m4a
    /// Embed subtitles in the video (MP4, MKV, WebM).
    var subtitles: Bool = false
    var videoContainer: VideoContainer = .mp4
    /// Save the subtitles as an `.srt` file next to the video or audio.
    var subtitleFile: Bool = false

    init(kind: MediaKind, videoQuality: VideoQuality = .p1080,
         audioBitrate: AudioBitrate = .k192, audioFormat: AudioFormat = .m4a,
         subtitles: Bool = false, videoContainer: VideoContainer = .mp4,
         subtitleFile: Bool = false) {
        self.kind = kind
        self.videoQuality = videoQuality
        self.audioBitrate = audioBitrate
        self.audioFormat = audioFormat
        self.subtitles = subtitles
        self.videoContainer = videoContainer
        self.subtitleFile = subtitleFile
    }

    /// Every field but `kind` may be missing: `pending.json` written by an
    /// older version has no `videoContainer`, and failing to read it would
    /// lose the downloads waiting to be resumed.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(MediaKind.self, forKey: .kind)
        videoQuality = try c.decodeIfPresent(VideoQuality.self, forKey: .videoQuality) ?? .p1080
        audioBitrate = try c.decodeIfPresent(AudioBitrate.self, forKey: .audioBitrate) ?? .k192
        audioFormat = try c.decodeIfPresent(AudioFormat.self, forKey: .audioFormat) ?? .m4a
        subtitles = try c.decodeIfPresent(Bool.self, forKey: .subtitles) ?? false
        videoContainer = try c.decodeIfPresent(VideoContainer.self, forKey: .videoContainer) ?? .mp4
        subtitleFile = try c.decodeIfPresent(Bool.self, forKey: .subtitleFile) ?? false
    }

    var shortLabel: String {
        switch kind {
        case .video: return "\(videoContainer.label) · \(videoQuality.label)"
        case .audio:
            if audioFormat.usesBitrate { return "\(audioFormat.label) · \(audioBitrate.label)" }
            return audioFormat.keepsOriginal ? "\(audioFormat.label) · original" : audioFormat.label
        }
    }

    /// The format a part of the video is actually written in (see
    /// `VideoContainer.forClip`).
    func forClip() -> DownloadFormat {
        var format = self
        format.videoContainer = videoContainer.forClip()
        return format
    }
}

extension VideoQuality: Codable {}
extension AudioBitrate: Codable {}
