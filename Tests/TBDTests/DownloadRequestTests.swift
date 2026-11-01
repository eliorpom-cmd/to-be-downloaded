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
}
