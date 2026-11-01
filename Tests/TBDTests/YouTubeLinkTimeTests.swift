// TBD — To Be Downloaded. Copyright (C) 2026 Elior Pommier.
// Licensed under the GNU AGPL v3 or later. See LICENSE and NOTICE.
import XCTest

final class YouTubeLinkTimeTests: XCTestCase {

    // MARK: - Start time carried by a link

    func testStartTimeFromTParameter() {
        XCTAssertEqual(
            YouTubeLink.startTime(from: "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=220"), 220)
    }

    func testStartTimeFromShortLinkWithUnitForm() {
        XCTAssertEqual(
            YouTubeLink.startTime(from: "https://youtu.be/dQw4w9WgXcQ?t=3m40s"), 220)
    }

    func testStartTimeFromFragment() {
        XCTAssertEqual(
            YouTubeLink.startTime(from: "https://www.youtube.com/watch?v=dQw4w9WgXcQ#t=1:02"), 62)
    }

    func testStartTimeFromStartParameter() {
        XCTAssertEqual(
            YouTubeLink.startTime(from: "https://www.youtube.com/watch?v=dQw4w9WgXcQ&start=30"), 30)
    }

    func testStartTimeIsNilWithoutTimeParameter() {
        XCTAssertNil(YouTubeLink.startTime(from: "https://www.youtube.com/watch?v=dQw4w9WgXcQ"))
    }

    func testStartTimeIsNilForZero() {
        XCTAssertNil(YouTubeLink.startTime(from: "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=0"))
    }

    func testStartTimeIsNilForNonYouTubeHost() {
        XCTAssertNil(YouTubeLink.startTime(from: "https://example.com/watch?v=x&t=10"))
    }

    // MARK: - Inserting a suffix before the extension

    func testSuffixGoesBeforeExtension() {
        XCTAssertEqual(
            FilenameTemplate.inserting(suffix: " (0m30s\u{2013}1m10s)", into: "%(title)s.%(ext)s"),
            "%(title)s (0m30s\u{2013}1m10s).%(ext)s")
    }

    func testPercentInSuffixIsDoubled() {
        XCTAssertEqual(
            FilenameTemplate.inserting(suffix: " 100%", into: "%(title)s.%(ext)s"),
            "%(title)s 100%%.%(ext)s")
    }

    func testSuffixAppendedWhenPatternHasNoExtension() {
        XCTAssertEqual(
            FilenameTemplate.inserting(suffix: " (x)", into: "custom"),
            "custom (x)")
    }
}
