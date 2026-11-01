// TBD — To Be Downloaded. Copyright (C) 2026 Elior Pommier.
// Licensed under the GNU AGPL v3 or later. See LICENSE and NOTICE.
import XCTest

final class JSRuntimeTests: XCTestCase {

    func testBundledQuickJSAlone() {
        let args = BinaryLocator.jsRuntimeArguments(
            bundledQuickJS: "/App/bin/qjs", isExecutable: { _ in false })
        XCTAssertEqual(args, ["--js-runtimes", "quickjs:/App/bin/qjs"])
    }

    func testUserDenoIsAddedFirst() {
        let args = BinaryLocator.jsRuntimeArguments(
            bundledQuickJS: "/App/bin/qjs",
            isExecutable: { $0 == "/opt/homebrew/bin/deno" })
        XCTAssertEqual(args, [
            "--js-runtimes", "deno:/opt/homebrew/bin/deno",
            "--js-runtimes", "quickjs:/App/bin/qjs",
        ])
    }

    func testOnlyOneDenoEvenIfSeveralExist() {
        let args = BinaryLocator.jsRuntimeArguments(
            bundledQuickJS: nil, isExecutable: { $0.hasSuffix("deno") })
        XCTAssertEqual(args, ["--js-runtimes", "deno:/opt/homebrew/bin/deno"])
    }

    func testNothingFound() {
        XCTAssertEqual(
            BinaryLocator.jsRuntimeArguments(bundledQuickJS: nil, isExecutable: { _ in false }),
            [])
    }
}
