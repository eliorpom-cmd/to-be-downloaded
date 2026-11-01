// TBD — To Be Downloaded. Copyright (C) 2026 Elior Pommier.
// Licensed under the GNU AGPL v3 or later. See LICENSE and NOTICE.
import XCTest

final class ProblemReportTests: XCTestCase {

    private func query(_ url: URL?) -> [String: String] {
        let items = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?
            .queryItems ?? []
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }

    func testFillsTheBugReportForm() {
        let url = ProblemReport.issueURL(
            repository: "eliorpom-cmd/to-be-downloaded",
            details: .init(appVersion: "1.3.0", ytDlpVersion: "2026.08.19",
                           updateChannel: "Stable", macOSVersion: "macOS 26.1 (25B78)",
                           macModel: "Mac14,2"))
        XCTAssertEqual(url?.host, "github.com")
        XCTAssertEqual(url?.path, "/eliorpom-cmd/to-be-downloaded/issues/new")
        let q = query(url)
        XCTAssertEqual(q["template"], "bug_report.yml")
        XCTAssertEqual(q["app-version"], "1.3.0")
        XCTAssertEqual(q["ytdlp-version"], "2026.08.19 (Stable)")
        XCTAssertEqual(q["macos"], "macOS 26.1 (25B78), Mac14,2")
    }

    func testUnknownYtDlpAndModel() {
        let q = query(ProblemReport.issueURL(
            repository: "a/b",
            details: .init(appVersion: "1.3.0", ytDlpVersion: nil, updateChannel: "Nightly",
                           macOSVersion: "macOS 15.3", macModel: nil)))
        XCTAssertEqual(q["ytdlp-version"], "unknown (Nightly)")
        XCTAssertEqual(q["macos"], "macOS 15.3")
    }

    /// The query keys must match the form's field ids, or GitHub leaves the
    /// fields empty without a word.
    func testKeysMatchTheIssueTemplate() throws {
        let template = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".github/ISSUE_TEMPLATE/bug_report.yml")
        let yaml = try String(contentsOf: template, encoding: .utf8)
        for id in ["app-version", "ytdlp-version", "macos"] {
            XCTAssertTrue(yaml.contains("id: \(id)\n"), "missing field id \(id)")
        }
    }

    func testCurrentMacOSVersionLooksRight() {
        XCTAssertTrue(ProblemReport.currentMacOSVersion.hasPrefix("macOS "))
    }
}
