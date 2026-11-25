// TBD — To Be Downloaded. Copyright (C) 2026 Elior Pommier.
// Licensed under the GNU AGPL v3 or later. See LICENSE and NOTICE.
import XCTest

final class DownloadRequestTests: XCTestCase {

    private func decode(_ json: String) throws -> DownloadRequestDTO {
        try JSONDecoder().decode(DownloadRequestDTO.self, from: Data(json.utf8))
    }

    func testWithoutTimesIsTheWholeVideo() throws {
        let dto = try decode(#"{"url":"https://youtu.be/dQw4w9WgXcQ","kind":"video","quality":"720"}"#)
        XCTAssertNil(dto.clipRange)
    }

    func testStartAndEndMakeARange() throws {
        let dto = try decode(#"{"url":"u","kind":"audio","quality":"","start":30,"end":90.5}"#)
        XCTAssertEqual(dto.clipRange, ClipRange(start: 30, end: 90.5))
    }

    func testReversedOrHalfRangeIsIgnored() throws {
        XCTAssertNil(try decode(#"{"url":"u","kind":"video","quality":null,"start":90,"end":30}"#).clipRange)
        XCTAssertNil(try decode(#"{"url":"u","kind":"video","quality":null,"start":30}"#).clipRange)
    }

    func testClipLabelCarriesTheRange() {
        let job = DownloadJob(url: "u", format: DownloadFormat(kind: .video, videoQuality: .p720),
                              range: ClipRange(start: 220, end: 435))
        XCTAssertEqual(job.formatLabel, "MP4 · 720p · 3:40–7:15")
        XCTAssertEqual(JobDTO(job).format, "MP4 · 720p · 3:40–7:15")
    }

    /// A huge end through the API must be refused, not trap in `Int(...)`.
    func testHugeTimeIsRefused() throws {
        XCTAssertNil(try decode(#"{"url":"u","kind":"video","quality":null,"start":0,"end":1e19}"#).clipRange)
        XCTAssertFalse(ClipRange(start: 0, end: .infinity).isValid)
    }

    func testTimeFormattingNeverTraps() {
        XCTAssertEqual(ClipRange.clock(1e19), "100:00:00")
        XCTAssertEqual(ClipRange.clock(.nan), "0:00")
        XCTAssertEqual(ClipRange(start: 0, end: 1e20).filenameSuffix, " (0m00s–100h00m00s)")
    }

    func testM4AClipKeepsOriginalOpusClipDoesNot() {
        var m4a = DownloadFormat(kind: .audio)
        m4a.audioFormat = .m4a
        let range = ClipRange(start: 0, end: 10)
        XCTAssertEqual(DownloadJob(url: "u", format: m4a, range: range).formatLabel,
                       "M4A · original · 0:00–0:10")
        var opus = m4a
        opus.audioFormat = .opus
        XCTAssertEqual(DownloadJob(url: "u", format: opus, range: range).formatLabel,
                       "OPUS · 0:00–0:10")
    }

    func testMOVMaxClipUses1080pRate() {
        XCTAssertEqual(DownloadEngine.clipVideoKilobits(for: .max, container: .mov),
                       DownloadEngine.clipVideoKilobits(for: .p1080))
        XCTAssertEqual(DownloadEngine.clipVideoKilobits(for: .max, container: .mp4), 24_000)
    }
}
