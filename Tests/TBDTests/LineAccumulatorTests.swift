// TBD — To Be Downloaded. Copyright (C) 2026 Elior Pommier.
// Licensed under the GNU AGPL v3 or later. See LICENSE and NOTICE.
import XCTest

final class LineAccumulatorTests: XCTestCase {

    private func data(_ text: String) -> Data {
        Data(text.utf8)
    }

    func testSplitsOnNewlines() {
        let accumulator = LineAccumulator()
        XCTAssertEqual(accumulator.append(data("a\nb\n")), ["a", "b"])
    }

    func testKeepsPartialLineUntilNewlineArrives() {
        let accumulator = LineAccumulator()
        XCTAssertEqual(accumulator.append(data("par")), [])
        XCTAssertEqual(accumulator.append(data("tial\n")), ["partial"])
    }

    func testCarriageReturnEndsALine() {
        let accumulator = LineAccumulator()
        let lines = accumulator.append(data("frame=1 time=00:00:01.00\rframe=2 time=00:00:02.00\r"))
        XCTAssertEqual(lines, ["frame=1 time=00:00:01.00", "frame=2 time=00:00:02.00"])
    }

    func testCRLFGivesOneLineWithoutEmptyStrings() {
        let accumulator = LineAccumulator()
        XCTAssertEqual(accumulator.append(data("a\r\nb\r\n")), ["a", "b"])
    }
}
