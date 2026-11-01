// TBD — To Be Downloaded. Copyright (C) 2026 Elior Pommier.
// Licensed under the GNU AGPL v3 or later. See LICENSE and NOTICE.
import XCTest

final class ClipRangeTests: XCTestCase {

    // MARK: - Reading times

    func testParseTimeAcceptsPlainSeconds() {
        XCTAssertEqual(ClipRange.parseTime("220"), 220)
        XCTAssertEqual(ClipRange.parseTime("220.5"), 220.5)
        XCTAssertEqual(ClipRange.parseTime("90s"), 90)
        XCTAssertEqual(ClipRange.parseTime(" 3:40 "), 220)
    }

    func testParseTimeAcceptsClockForms() {
        XCTAssertEqual(ClipRange.parseTime("3:40"), 220)
        XCTAssertEqual(ClipRange.parseTime("1:02:00"), 3720)
    }

    func testParseTimeAcceptsUnitForms() {
        XCTAssertEqual(ClipRange.parseTime("3m40s"), 220)
        XCTAssertEqual(ClipRange.parseTime("1h2m"), 3720)
        // Trailing digits without a unit are seconds.
        XCTAssertEqual(ClipRange.parseTime("3m40"), 220)
    }

    func testParseTimeRejectsMalformedInput() {
        XCTAssertNil(ClipRange.parseTime(""))
        XCTAssertNil(ClipRange.parseTime("abc"))
        XCTAssertNil(ClipRange.parseTime("1:75"))
        XCTAssertNil(ClipRange.parseTime("1:2:3:4"))
        XCTAssertNil(ClipRange.parseTime("3mm"))
        XCTAssertNil(ClipRange.parseTime("-5"))
        XCTAssertNil(ClipRange.parseTime("1.5:00"))
    }

    // MARK: - Writing times

    func testClockFormatting() {
        XCTAssertEqual(ClipRange.clock(220), "3:40")
        XCTAssertEqual(ClipRange.clock(3720), "1:02:00")
        // Rounded down to whole seconds.
        XCTAssertEqual(ClipRange.clock(59.9), "0:59")
    }

    func testCompactFormatting() {
        XCTAssertEqual(ClipRange.compact(220), "3m40s")
        XCTAssertEqual(ClipRange.compact(3720), "1h02m00s")
    }

    // MARK: - yt-dlp and file name

    func testSectionArgumentUsesTimeRangeMarker() {
        XCTAssertEqual(ClipRange(start: 220, end: 435).sectionArgument, "*220-435")
        XCTAssertEqual(ClipRange(start: 1.5, end: 10.25).sectionArgument, "*1.5-10.25")
    }

    func testFilenameSuffixAndLabel() {
        let range = ClipRange(start: 220, end: 435)
        // En dash (U+2013), as in the file name the app produces.
        XCTAssertEqual(range.filenameSuffix, " (3m40s\u{2013}7m15s)")
        XCTAssertEqual(range.label, "3:40\u{2013}7:15")
    }

    // MARK: - Normalization of several ranges

    func testNormalizedClampsEndToDuration() {
        let result = ClipRange.normalized([ClipRange(start: 0, end: 100)], duration: 50)
        XCTAssertEqual(result, [ClipRange(start: 0, end: 50)])
    }

    func testNormalizedDropsRangesStartingAfterDuration() {
        let result = ClipRange.normalized([ClipRange(start: 60, end: 100)], duration: 50)
        XCTAssertTrue(result.isEmpty)
    }

    func testNormalizedDropsEmptyRanges() {
        let result = ClipRange.normalized([ClipRange(start: 10, end: 10)], duration: nil)
        XCTAssertTrue(result.isEmpty)
    }

    func testNormalizedSortsRanges() {
        let result = ClipRange.normalized([
            ClipRange(start: 30, end: 40),
            ClipRange(start: 0, end: 10),
        ], duration: nil)
        XCTAssertEqual(result, [
            ClipRange(start: 0, end: 10),
            ClipRange(start: 30, end: 40),
        ])
    }

    func testNormalizedMergesOverlappingRanges() {
        let result = ClipRange.normalized([
            ClipRange(start: 0, end: 10),
            ClipRange(start: 5, end: 20),
        ], duration: nil)
        XCTAssertEqual(result, [ClipRange(start: 0, end: 20)])
    }

    func testNormalizedMergesTouchingRanges() {
        let result = ClipRange.normalized([
            ClipRange(start: 0, end: 10),
            ClipRange(start: 10, end: 15),
        ], duration: nil)
        XCTAssertEqual(result, [ClipRange(start: 0, end: 15)])
    }

    func testNormalizedKeepsDisjointRanges() {
        let result = ClipRange.normalized([
            ClipRange(start: 0, end: 10),
            ClipRange(start: 20, end: 30),
        ], duration: nil)
        XCTAssertEqual(result, [
            ClipRange(start: 0, end: 10),
            ClipRange(start: 20, end: 30),
        ])
    }

    func testNormalizedClampsNegativeStartToZero() {
        let result = ClipRange.normalized([ClipRange(start: -5, end: 10)], duration: nil)
        XCTAssertEqual(result, [ClipRange(start: 0, end: 10)])
    }

    func testNormalizedDoesNotClampWithoutDuration() {
        let result = ClipRange.normalized([ClipRange(start: 0, end: 10_000)], duration: nil)
        XCTAssertEqual(result, [ClipRange(start: 0, end: 10_000)])
    }

    // MARK: - FFmpeg progress lines

    func testFFmpegProgressReadsTime() {
        let line = "frame=  250 fps= 16 q=-0.0 Lsize=   12544KiB time=00:00:10.00 bitrate=10268.0kbits/s speed=0.63x"
        XCTAssertEqual(FFmpegProgress.time(in: line) ?? -1, 10.0, accuracy: 0.001)
    }

    func testFFmpegProgressIgnoresNotAvailableTime() {
        XCTAssertNil(FFmpegProgress.time(in: "size=N/A time=N/A bitrate=N/A"))
    }

    func testFFmpegProgressIgnoresLineWithoutTime() {
        XCTAssertNil(FFmpegProgress.time(in: "Input #0, mov,mp4,m4a, from 'video.mp4':"))
    }

    func testFFmpegProgressClampsNegativeTimeToZero() {
        XCTAssertEqual(FFmpegProgress.time(in: "time=-00:00:00.02"), 0)
    }
}
