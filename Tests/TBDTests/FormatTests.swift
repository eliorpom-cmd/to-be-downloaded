// TBD — To Be Downloaded. Copyright (C) 2026 Elior Pommier.
// Licensed under the GNU AGPL v3 or later. See LICENSE and NOTICE.
import XCTest

final class FormatTests: XCTestCase {

    private var config: DownloadEngine.Config {
        DownloadEngine.Config(
            ytDlp: URL(fileURLWithPath: "/bin/yt-dlp"),
            ffmpegDirectory: URL(fileURLWithPath: "/ff"),
            outputDirectory: URL(fileURLWithPath: "/out"),
            trustBundle: nil)
    }

    private let url = "https://www.youtube.com/watch?v=dQw4w9WgXcQ"

    private func arguments(
        format: DownloadFormat,
        range: ClipRange? = nil,
        config: DownloadEngine.Config? = nil
    ) -> [String] {
        DownloadEngine.downloadArguments(
            url: url,
            format: format,
            range: range,
            config: config ?? self.config,
            resultFile: URL(fileURLWithPath: "/work/result.txt"),
            workDir: URL(fileURLWithPath: "/work"))
    }

    /// Returns the argument that follows `flag`, or `nil` if the flag is absent.
    private func value(after flag: String, in args: [String]) -> String? {
        guard let index = args.firstIndex(of: flag), index + 1 < args.count else { return nil }
        return args[index + 1]
    }

    /// Splits a yt-dlp `-f` selector into its `/`-separated choices.
    private func choices(of selector: String) -> [String] {
        selector.split(separator: "/").map(String.init)
    }

    // MARK: - Default container

    func testDefaultContainerIsMP4() {
        let format = DownloadFormat(kind: .video)
        XCTAssertEqual(format.videoContainer, .mp4)
        XCTAssertEqual(format.shortLabel, "MP4 \u{00B7} 1080p")
    }

    func testMKVShortLabel() {
        let format = DownloadFormat(kind: .video, videoQuality: .p1080, videoContainer: .mkv)
        XCTAssertEqual(format.shortLabel, "MKV \u{00B7} 1080p")
    }

    // MARK: - Decoding and round trip

    func testDecodingOldVideoJSONDefaultsContainerToMP4() throws {
        let json = #"{"kind":"video","videoQuality":720,"audioBitrate":192,"audioFormat":"m4a","subtitles":false}"#
        let format = try JSONDecoder().decode(DownloadFormat.self, from: Data(json.utf8))
        XCTAssertEqual(format.kind, .video)
        XCTAssertEqual(format.videoContainer, .mp4)
        XCTAssertEqual(format.videoQuality, .p720)
    }

    func testDecodingKindOnlyJSONUsesDefaults() throws {
        let format = try JSONDecoder().decode(DownloadFormat.self, from: Data(#"{"kind":"audio"}"#.utf8))
        XCTAssertEqual(format.kind, .audio)
        XCTAssertEqual(format.videoQuality, .p1080)
        XCTAssertEqual(format.audioBitrate, .k192)
        XCTAssertEqual(format.audioFormat, .m4a)
        XCTAssertFalse(format.subtitles)
        XCTAssertEqual(format.videoContainer, .mp4)
    }

    func testWebMRoundTripPreservesFormat() throws {
        let original = DownloadFormat(kind: .video, videoQuality: .max, subtitles: true,
                                      videoContainer: .webm)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DownloadFormat.self, from: data)
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.videoContainer, .webm)
    }

    // MARK: - Container remux arguments

    func testMergeOutputFormatFollowsEachContainer() {
        for container in VideoContainer.allCases {
            let args = arguments(format: DownloadFormat(kind: .video, videoContainer: container))
            XCTAssertEqual(value(after: "--merge-output-format", in: args), container.rawValue,
                           "Wrong merge format for \(container)")
        }
    }

    func testNoContainerRequestsReencoding() {
        for container in VideoContainer.allCases {
            let args = arguments(format: DownloadFormat(kind: .video, videoContainer: container))
            XCTAssertFalse(args.contains("--recode-video"), "Remux only, for \(container)")
        }
    }

    // MARK: - MOV

    func testMOVSelectorOnlyAllowsH264AndAAC() {
        let args = arguments(format: DownloadFormat(kind: .video, videoQuality: .p1080, videoContainer: .mov))
        let selector = value(after: "-f", in: args) ?? ""
        let parts = choices(of: selector)
        XCTAssertFalse(parts.isEmpty)
        for part in parts {
            XCTAssertTrue(part.contains("avc1"), "Non-H.264 choice in MOV selector: \(part)")
        }
    }

    func testMOVMaxSortsByHeight1080() {
        let args = arguments(format: DownloadFormat(kind: .video, videoQuality: .max, videoContainer: .mov))
        XCTAssertEqual(value(after: "-S", in: args), "res:1080")
    }

    func testMOVWithSubtitlesDoesNotEmbedSubtitles() {
        let args = arguments(format: DownloadFormat(kind: .video, videoQuality: .p1080,
                                                    subtitles: true, videoContainer: .mov))
        XCTAssertFalse(args.contains("--embed-subs"))
    }

    // MARK: - WebM

    func testWebMSelectorOnlyAllowsWebMStreams() {
        let args = arguments(format: DownloadFormat(kind: .video, videoQuality: .p1080, videoContainer: .webm))
        let selector = value(after: "-f", in: args) ?? ""
        let parts = choices(of: selector)
        XCTAssertFalse(parts.isEmpty)
        for part in parts {
            XCTAssertTrue(part.contains("[ext=webm]"), "Non-WebM choice in WebM selector: \(part)")
        }
    }

    func testWebMMaxSelectorIsExact() {
        let args = arguments(format: DownloadFormat(kind: .video, videoQuality: .max, videoContainer: .webm))
        XCTAssertEqual(value(after: "-f", in: args), "bv*[ext=webm]+ba[ext=webm]")
    }

    // MARK: - Subtitles per container

    func testMKVWithSubtitlesEmbedsAndConvertsToSRT() {
        let args = arguments(format: DownloadFormat(kind: .video, videoQuality: .p1080,
                                                    subtitles: true, videoContainer: .mkv))
        XCTAssertTrue(args.contains("--embed-subs"))
        XCTAssertEqual(value(after: "--convert-subs", in: args), "srt")
    }

    func testMP4WithSubtitlesEmbedsWithoutConversion() {
        let args = arguments(format: DownloadFormat(kind: .video, videoQuality: .p1080,
                                                    subtitles: true, videoContainer: .mp4))
        XCTAssertTrue(args.contains("--embed-subs"))
        XCTAssertFalse(args.contains("--convert-subs"))
    }

    // MARK: - WebM clip

    func testWebMClipIsWrittenAsMP4() {
        let args = arguments(format: DownloadFormat(kind: .video, videoQuality: .p720, videoContainer: .webm),
                             range: ClipRange(start: 10, end: 20))
        XCTAssertEqual(value(after: "--merge-output-format", in: args), "mp4")
        XCTAssertTrue(args.contains("--downloader-args"))
    }

    func testForClipMapsWebMToMP4() {
        let format = DownloadFormat(kind: .video, videoContainer: .webm).forClip()
        XCTAssertEqual(format.videoContainer, .mp4)
    }

    func testForClipKeepsMKV() {
        let format = DownloadFormat(kind: .video, videoContainer: .mkv).forClip()
        XCTAssertEqual(format.videoContainer, .mkv)
    }

    func testWebMClipFormatLabelShowsMP4() {
        let job = DownloadJob(url: "u",
                              format: DownloadFormat(kind: .video, videoQuality: .p720, videoContainer: .webm),
                              range: ClipRange(start: 220, end: 435))
        XCTAssertEqual(job.formatLabel, "MP4 \u{00B7} 720p \u{00B7} 3:40\u{2013}7:15")
    }

    // MARK: - Audio selectors and formats

    func testOpusWholeSelectorAndFormat() {
        let args = arguments(format: DownloadFormat(kind: .audio, audioFormat: .opus))
        XCTAssertEqual(value(after: "-f", in: args), "ba[acodec=opus]/ba/b")
        XCTAssertEqual(value(after: "--audio-format", in: args), "opus")
    }

    func testOpusClipSelectorUsesAAC() {
        let args = arguments(format: DownloadFormat(kind: .audio, audioFormat: .opus),
                             range: ClipRange(start: 220, end: 435))
        XCTAssertEqual(value(after: "-f", in: args), "ba[ext=m4a]/ba")
    }

    func testFLACAudioFormatArgument() {
        let args = arguments(format: DownloadFormat(kind: .audio, audioFormat: .flac))
        XCTAssertEqual(value(after: "--audio-format", in: args), "flac")
    }

    func testWAVAudioFormatArgument() {
        let args = arguments(format: DownloadFormat(kind: .audio, audioFormat: .wav))
        XCTAssertEqual(value(after: "--audio-format", in: args), "wav")
    }

    func testOpusShortLabelIsOriginal() {
        XCTAssertEqual(DownloadFormat(kind: .audio, audioFormat: .opus).shortLabel, "OPUS \u{00B7} original")
    }

    func testFLACShortLabel() {
        XCTAssertEqual(DownloadFormat(kind: .audio, audioFormat: .flac).shortLabel, "FLAC")
    }

    func testMP3ShortLabelShowsBitrate() {
        let format = DownloadFormat(kind: .audio, audioBitrate: .k320, audioFormat: .mp3)
        XCTAssertEqual(format.shortLabel, "MP3 \u{00B7} 320 kbps")
    }

    func testUsesBitrateOnlyForMP3() {
        for format in AudioFormat.allCases {
            XCTAssertEqual(format.usesBitrate, format == .mp3, "usesBitrate for \(format)")
        }
    }

    func testKeepsOriginalOnlyForM4AAndOpus() {
        for format in AudioFormat.allCases {
            XCTAssertEqual(format.keepsOriginal, format == .m4a || format == .opus,
                           "keepsOriginal for \(format)")
        }
    }

    // MARK: - Estimated sizes

    func testEstimatedBytesWAV() {
        let metadata = MediaMetadata(title: "t", duration: 100)
        let format = DownloadFormat(kind: .audio, audioFormat: .wav)
        let bytes = metadata.estimatedBytes(for: format) ?? -1
        XCTAssertEqual(Double(bytes), 19_200_000, accuracy: 1)
    }

    func testEstimatedBytesFLAC() {
        let metadata = MediaMetadata(title: "t", duration: 100)
        let format = DownloadFormat(kind: .audio, audioFormat: .flac)
        let bytes = metadata.estimatedBytes(for: format) ?? -1
        XCTAssertEqual(Double(bytes), 11_520_000, accuracy: 1)
    }
}
