// TBD — To Be Downloaded. Copyright (C) 2026 Elior Pommier.
// Licensed under the GNU AGPL v3 or later. See LICENSE and NOTICE.
import XCTest

final class CookieBrowserTests: XCTestCase {

    // MARK: - yt-dlp arguments

    func testNoArgumentsWhenOptionIsOff() {
        XCTAssertEqual(CookieBrowser.arguments(for: nil), [])
    }

    func testChromeArguments() {
        XCTAssertEqual(CookieBrowser.arguments(for: .chrome),
                       ["--cookies-from-browser", "chrome"])
    }

    func testSafariArguments() {
        XCTAssertEqual(CookieBrowser.arguments(for: .safari),
                       ["--cookies-from-browser", "safari"])
    }

    // MARK: - Installed browsers

    func testInstalledBrowsersFollowAllCasesOrder() {
        let installed: Set<String> = ["com.apple.Safari", "com.google.Chrome"]
        XCTAssertEqual(CookieBrowser.installed(isInstalled: { installed.contains($0) }),
                       [.safari, .chrome])
    }

    func testNoInstalledBrowsers() {
        XCTAssertEqual(CookieBrowser.installed(isInstalled: { _ in false }), [])
    }

    // MARK: - Keychain and Full Disk Access

    func testKeychainUsageForSafariAndFirefoxIsFalse() {
        XCTAssertFalse(CookieBrowser.safari.usesKeychain)
        XCTAssertFalse(CookieBrowser.firefox.usesKeychain)
    }

    func testKeychainUsageForChromiumBrowsersIsTrue() {
        XCTAssertTrue(CookieBrowser.chrome.usesKeychain)
        XCTAssertTrue(CookieBrowser.brave.usesKeychain)
        XCTAssertTrue(CookieBrowser.edge.usesKeychain)
    }

    func testChromeKeychainItemName() {
        XCTAssertEqual(CookieBrowser.chrome.keychainItem, "Chrome Safe Storage")
    }

    func testSafariHasNoKeychainItem() {
        XCTAssertNil(CookieBrowser.safari.keychainItem)
    }

    func testOnlySafariNeedsFullDiskAccess() {
        for browser in CookieBrowser.allCases {
            XCTAssertEqual(browser.needsFullDiskAccess, browser == .safari,
                           "Unexpected Full Disk Access flag for \(browser)")
        }
    }

    // MARK: - Error explanations

    func testExplainsSafariPermissionFailure() {
        let message = "[Errno 1] Operation not permitted: '/Users/x/Library/Containers/"
            + "com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies'"
        let explanation = CookieBrowser.explain(message)
        XCTAssertNotNil(explanation)
        XCTAssertTrue(explanation?.contains("Full Disk Access") ?? false)
    }

    func testExplainsKeychainFailure() {
        let explanation = CookieBrowser.explain("Failed to decrypt with Chrome Safe Storage")
        XCTAssertNotNil(explanation)
        XCTAssertTrue(explanation?.contains("keychain") ?? false)
    }

    func testIgnoresUnrelatedErrors() {
        XCTAssertNil(CookieBrowser.explain("Video unavailable"))
    }

    // MARK: - DownloadEngine.cleanError

    func testCleanErrorExplainsSafariPermissionFailure() {
        let raw = "ERROR: [Errno 1] Operation not permitted: '/Users/x/Library/Containers/"
            + "com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies'"
        let message = DownloadEngine.cleanError(raw, code: 1)
        XCTAssertTrue(message.contains("Full Disk Access"))
    }

    func testCleanErrorStripsPrefixForOrdinaryErrors() {
        let message = DownloadEngine.cleanError(
            "ERROR: [youtube] abc: Video unavailable", code: 1)
        XCTAssertEqual(message, "[youtube] abc: Video unavailable")
    }

    // MARK: - Arguments reach yt-dlp

    func testBrowserFlagReachesDownloadArguments() {
        let config = DownloadEngine.Config(
            ytDlp: URL(fileURLWithPath: "/y"),
            ffmpegDirectory: URL(fileURLWithPath: "/f"),
            outputDirectory: URL(fileURLWithPath: "/o"),
            trustBundle: nil,
            commonArguments: CookieBrowser.arguments(for: .firefox))
        let args = DownloadEngine.downloadArguments(
            url: "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
            format: DownloadFormat(kind: .video),
            range: nil,
            config: config,
            resultFile: URL(fileURLWithPath: "/work/result.txt"),
            workDir: URL(fileURLWithPath: "/work"))
        guard let index = args.firstIndex(of: "--cookies-from-browser") else {
            XCTFail("--cookies-from-browser is missing from the arguments")
            return
        }
        XCTAssertEqual(args[index + 1], "firefox")
    }
}
