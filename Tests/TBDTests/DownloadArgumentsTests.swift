// TBD — To Be Downloaded. Copyright (C) 2026 Elior Pommier.
// Licensed under the GNU AGPL v3 or later. See LICENSE and NOTICE.
import XCTest

final class DownloadArgumentsTests: XCTestCase {

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
    func value(after flag: String, in args: [String]) -> String? {
        guard let index = args.firstIndex(of: flag), index + 1 < args.count else { return nil }
        return args[index + 1]
    }

    // MARK: - Whole video

    func testWholeVideoHasNoSectionsOrDownloaderArgs() {
        let args = arguments(format: DownloadFormat(kind: .video, videoQuality: .p1080))
        XCTAssertFalse(args.contains("--download-sections"))
        XCTAssertFalse(args.contains("--downloader-args"))
    }

    func testWholeVideoSelectorKeepsMuxedFallback() {
        let args = arguments(format: DownloadFormat(kind: .video, videoQuality: .p1080))
        let selector = value(after: "-f", in: args) ?? ""
        XCTAssertTrue(selector.contains("b[height<=1080]"))
        XCTAssertTrue(selector.hasSuffix("/b"))
    }

    func testURLIsLastAndPrecededByDoubleDash() {
        let args = arguments(format: DownloadFormat(kind: .video, videoQuality: .p1080))
        XCTAssertEqual(args.last, url)
        XCTAssertEqual(args[args.count - 2], "--")
    }

    func testOutputPatternWithoutRange() {
        let args = arguments(format: DownloadFormat(kind: .video, videoQuality: .p1080))
        XCTAssertEqual(value(after: "-o", in: args), "%(title)s.%(ext)s")
    }

    // MARK: - Clip

    func testClipUsesDownloadSections() {
        let args = arguments(format: DownloadFormat(kind: .video, videoQuality: .p1080),
                             range: ClipRange(start: 220, end: 435))
        XCTAssertEqual(value(after: "--download-sections", in: args), "*220-435")
    }

    func testClipSelectorHasNoMuxedFallback() {
        let args = arguments(format: DownloadFormat(kind: .video, videoQuality: .p1080),
                             range: ClipRange(start: 220, end: 435))
        let selector = value(after: "-f", in: args) ?? ""
        let components = selector.split(separator: "/").map(String.init)
        XCTAssertFalse(components.contains("b"))
        XCTAssertFalse(components.contains { $0.hasPrefix("b[") })
    }

    func testClipReencodesWithVideoToolbox() {
        let args = arguments(format: DownloadFormat(kind: .video, videoQuality: .p1080),
                             range: ClipRange(start: 220, end: 435))
        let downloaderArgs = value(after: "--downloader-args", in: args) ?? ""
        XCTAssertTrue(downloaderArgs.hasPrefix("ffmpeg_o:"))
        XCTAssertTrue(downloaderArgs.contains("h264_videotoolbox"))
        XCTAssertTrue(downloaderArgs.contains("-c:a copy"))
    }

    func testClipOutputPatternCarriesRangeSuffix() {
        let args = arguments(format: DownloadFormat(kind: .video, videoQuality: .p1080),
                             range: ClipRange(start: 220, end: 435))
        XCTAssertEqual(value(after: "-o", in: args), "%(title)s (3m40s\u{2013}7m15s).%(ext)s")
    }

    func testClipMergesToMP4() {
        let args = arguments(format: DownloadFormat(kind: .video, videoQuality: .p1080),
                             range: ClipRange(start: 220, end: 435))
        XCTAssertEqual(value(after: "--merge-output-format", in: args), "mp4")
    }

    func testClipWithSubtitlesDoesNotEmbedSubtitles() {
        let args = arguments(format: DownloadFormat(kind: .video, videoQuality: .p1080, subtitles: true),
                             range: ClipRange(start: 220, end: 435))
        XCTAssertFalse(args.contains("--embed-subs"))
    }

    func testWholeVideoWithSubtitlesEmbedsSubtitles() {
        let args = arguments(format: DownloadFormat(kind: .video, videoQuality: .p1080, subtitles: true))
        XCTAssertTrue(args.contains("--embed-subs"))
    }

    func testMaxQualityClipSelectorIsBestStreamsOnly() {
        let args = arguments(format: DownloadFormat(kind: .video, videoQuality: .max),
                             range: ClipRange(start: 220, end: 435))
        XCTAssertEqual(value(after: "-f", in: args), "bv*+ba")
    }

    // MARK: - Audio

    func testAudioM4AClipSelector() {
        let args = arguments(format: DownloadFormat(kind: .audio, audioFormat: .m4a),
                             range: ClipRange(start: 220, end: 435))
        XCTAssertEqual(value(after: "-f", in: args), "ba[ext=m4a]/ba")
        XCTAssertFalse(args.contains("--downloader-args"))
    }

    func testAudioMP3ClipSelector() {
        let args = arguments(format: DownloadFormat(kind: .audio, audioFormat: .mp3),
                             range: ClipRange(start: 220, end: 435))
        XCTAssertEqual(value(after: "-f", in: args), "ba[ext=m4a]/ba")
    }

    func testAudioM4AWholeSelectorKeepsMuxedFallback() {
        let args = arguments(format: DownloadFormat(kind: .audio, audioFormat: .m4a))
        XCTAssertEqual(value(after: "-f", in: args), "ba[ext=m4a]/ba/b")
    }

    // MARK: - Config

    func testCommonArgumentsComeFirst() {
        var custom = config
        custom.commonArguments = ["--js-runtimes", "quickjs:/q"]
        let args = arguments(format: DownloadFormat(kind: .video, videoQuality: .p1080), config: custom)
        XCTAssertEqual(Array(args.prefix(2)), ["--js-runtimes", "quickjs:/q"])
    }
}
