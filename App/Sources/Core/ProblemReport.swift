// TBD — To Be Downloaded. Copyright (C) 2026 Elior Pommier.
// Licensed under the GNU AGPL v3 or later. See LICENSE and NOTICE.
import Foundation

/// "Report a Problem": a GitHub issue, pre-filled with what a bug report
/// always asks for.
///
/// Nothing is sent. The app only opens a page in the browser; the person
/// reads the text, completes it, and decides whether to post it. TBD has no
/// telemetry, so this is the one channel through which a problem on someone
/// else's Mac can reach the project at all.
enum ProblemReport {

    /// The versions that go into the report.
    struct Details: Equatable {
        var appVersion: String
        var ytDlpVersion: String?
        var updateChannel: String
        var macOSVersion: String
        var macModel: String?
    }

    /// `issues/new` with the bug report form chosen and its fields filled.
    /// The keys are the `id`s in `.github/ISSUE_TEMPLATE/bug_report.yml`:
    /// GitHub fills a form field from the query item of the same name.
    static func issueURL(repository: String, details: Details) -> URL? {
        var components = URLComponents(string: "https://github.com/\(repository)/issues/new")
        let ytDlp = details.ytDlpVersion.map { "\($0) (\(details.updateChannel))" }
            ?? "unknown (\(details.updateChannel))"
        let mac = [details.macOSVersion, details.macModel]
            .compactMap { $0 }
            .joined(separator: ", ")
        components?.queryItems = [
            URLQueryItem(name: "template", value: "bug_report.yml"),
            URLQueryItem(name: "app-version", value: details.appVersion),
            URLQueryItem(name: "ytdlp-version", value: ytDlp),
            URLQueryItem(name: "macos", value: mac),
        ]
        return components?.url
    }

    /// `macOS 26.1 (25B78)`.
    static var currentMacOSVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        let number = v.patchVersion > 0
            ? "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
            : "\(v.majorVersion).\(v.minorVersion)"
        let build = sysctlString("kern.osversion").map { " (\($0))" } ?? ""
        return "macOS \(number)\(build)"
    }

    /// Model identifier, `Mac14,2`. Says which chip without asking anyone
    /// to look it up.
    static var currentMacModel: String? { sysctlString("hw.model") }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        // The value ends with a NUL byte; drop it and anything after.
        let bytes = buffer.prefix { $0 != 0 }
        let value = String(decoding: bytes, as: UTF8.self)
        return value.isEmpty ? nil : value
    }
}
