// TBD — To Be Downloaded. Copyright (C) 2026 Elior Pommier.
// Licensed under the GNU AGPL v3 or later. See LICENSE and NOTICE.
import Foundation

/// A part of a video, in seconds from its start.
///
/// Only this part is ever downloaded: yt-dlp's `--download-sections` asks
/// YouTube for the bytes of the range (plus a second or two back to the
/// previous keyframe), never for the whole file. See
/// docs/research/partial-download.md.
struct ClipRange: Codable, Hashable, Sendable {
    var start: Double
    var end: Double

    init(start: Double, end: Double) {
        self.start = start
        self.end = end
    }

    var length: Double { max(0, end - start) }

    /// A range that can be downloaded: starts before it ends.
    var isValid: Bool { start >= 0 && end > start }

    /// Value of `--download-sections`. The leading `*` means "time range",
    /// as opposed to a chapter title regex.
    var sectionArgument: String {
        "*\(Self.decimal(start))-\(Self.decimal(end))"
    }

    /// Appended to the file name: `Title (3m40s–7m15s).mp4`.
    var filenameSuffix: String {
        " (\(Self.compact(start))–\(Self.compact(end)))"
    }

    /// Shown in the library and the capsules: `3:40–7:15`.
    var label: String {
        "\(Self.clock(start))–\(Self.clock(end))"
    }

    // MARK: - Several ranges

    /// Ranges ready to download: clamped to the duration, invalid ones
    /// dropped, sorted, and overlapping ones merged — two overlapping ranges
    /// would otherwise download the shared part twice. Ranges that only touch
    /// (two consecutive chapters) stay two files, as the editor shows them.
    static func normalized(_ ranges: [ClipRange], duration: Double?) -> [ClipRange] {
        let clamped: [ClipRange] = ranges.compactMap { range in
            var r = range
            r.start = max(0, r.start)
            if let duration, duration > 0 {
                r.end = min(r.end, duration)
            }
            return r.isValid ? r : nil
        }
        var merged: [ClipRange] = []
        for range in clamped.sorted(by: { $0.start < $1.start }) {
            if let last = merged.last, range.start < last.end {
                merged[merged.count - 1].end = max(last.end, range.end)
            } else {
                merged.append(range)
            }
        }
        return merged
    }

    // MARK: - Reading times

    /// Reads a time typed by a person or carried by a link.
    ///
    /// Accepts `220`, `220.5`, `3:40`, `1:02:00`, `3m40s`, `1h2m`, `90s`.
    /// Returns `nil` for anything else, rather than guessing.
    static func parseTime(_ raw: String) -> Double? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return nil }

        // Plain seconds.
        if let seconds = Double(text), seconds >= 0, seconds.isFinite {
            return seconds
        }

        // Clock form: m:ss or h:mm:ss. Every part but the first must be
        // below 60, or "1:75" would silently mean 2:15.
        if text.contains(":") {
            let parts = text.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
            guard (2...3).contains(parts.count) else { return nil }
            var total = 0.0
            for (index, part) in parts.enumerated() {
                guard !part.isEmpty, let value = Double(part), value >= 0 else { return nil }
                // Only the last part may carry decimals.
                if index < parts.count - 1, part.contains(".") { return nil }
                if index > 0, value >= 60 { return nil }
                total = total * 60 + value
            }
            return total
        }

        // Unit form: 1h2m3s, 3m40s, 90s, 2m.
        var total = 0.0
        var number = ""
        var seenUnits = Set<Character>()
        for char in text {
            if char.isNumber || char == "." {
                number.append(char)
                continue
            }
            let factor: Double
            switch char {
            case "h": factor = 3600
            case "m": factor = 60
            case "s": factor = 1
            default: return nil
            }
            guard !number.isEmpty, let value = Double(number),
                  !seenUnits.contains(char) else { return nil }
            seenUnits.insert(char)
            total += value * factor
            number = ""
        }
        // Trailing digits without a unit ("3m40") are seconds.
        if !number.isEmpty {
            guard let value = Double(number) else { return nil }
            total += value
        }
        return seenUnits.isEmpty && number.isEmpty ? nil : total
    }

    // MARK: - Writing times

    /// `3:40`, `1:02:00`. Whole seconds, rounded down: it is what a person
    /// reads on a player.
    static func clock(_ seconds: Double) -> String {
        let total = Int(max(0, seconds).rounded(.down))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }

    /// `3m40s`, `1h02m00s`: safe in a file name, unlike `:`, which Finder
    /// shows as `/`.
    static func compact(_ seconds: Double) -> String {
        let tenths = Int((max(0, seconds) * 10).rounded())
        let total = tenths / 10, fraction = tenths % 10
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        // Tenths only when present: "3m40s", but "3m40.5s" so that two clips
        // a fraction of a second apart do not get the same file name.
        let sec = fraction == 0 ? String(format: "%02ds", s) : String(format: "%02d.%ds", s, fraction)
        return h > 0
            ? String(format: "%dh%02dm", h, m) + sec
            : String(format: "%dm", m) + sec
    }

    /// Seconds for yt-dlp, without float noise (`220`, `220.5`).
    private static func decimal(_ seconds: Double) -> String {
        let rounded = (seconds * 1000).rounded() / 1000
        return rounded == rounded.rounded()
            ? String(Int(rounded))
            : String(format: "%.3f", rounded)
                .replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
    }
}

/// FFmpeg's progress line, which is all there is to read while yt-dlp hands a
/// range to FFmpeg: its own progress template stays silent until the end.
///
/// `frame=  250 fps= 16 q=-0.0 size=  12544KiB time=00:00:10.00 bitrate=…`
enum FFmpegProgress {
    /// Seconds of output written so far, or `nil` if the line is not a
    /// progress line (or says `time=N/A`).
    static func time(in line: String) -> Double? {
        guard let range = line.range(of: "time=") else { return nil }
        let rest = line[range.upperBound...]
        let token = rest.prefix { !$0.isWhitespace }
        guard !token.isEmpty, token != "N/A" else { return nil }
        let negative = token.hasPrefix("-")
        guard !negative else { return 0 }
        return ClipRange.parseTime(String(token))
    }
}
