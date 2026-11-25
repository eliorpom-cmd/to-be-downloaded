// TBD — To Be Downloaded. Copyright (C) 2026 Elior Pommier.
// Licensed under the GNU AGPL v3 or later. See LICENSE and NOTICE.
//
// Measures what one drag of a Trim handle costs, without showing anything.
//
// The real `TrimEditor` is hosted in a borderless window placed far off
// screen, under a parent that owns `ranges` the way `DownloadPane` does.
// Mouse events are built and handed to the window directly (`sendEvent`):
// the cursor never moves and nothing comes to the front. After each event
// the view is laid out and drawn, and the time it took is recorded.
//
// Usage: scripts/research/trim-drag-bench/run.sh <yt-dlp metadata.json>

import SwiftUI
import AppKit

/// Counts how often the parent's body runs: in the app, every one of these
/// is a full `DownloadPane` body (field, notices, format controls, session
/// list) re-evaluated.
@MainActor enum Probe {
    static var parentBodies = 0
    /// End of the first range as the parent last saw it: proof the drag
    /// reached the binding.
    static var lastEnd: Double?
}

struct Parent: View {
    @State var ranges: [ClipRange]
    @State var selection = 0
    let metadata: MediaMetadata

    var body: some View {
        let _ = { Probe.parentBodies += 1; Probe.lastEnd = ranges.first?.end }()
        VStack(alignment: .leading, spacing: 12) {
            TrimEditor(ranges: $ranges, selection: $selection,
                       duration: metadata.duration ?? 0, metadata: metadata,
                       format: DownloadFormat(kind: .video))
            // What DownloadPane derives from the ranges on every pass.
            Text(ClipRange.normalized(ranges, duration: metadata.duration)
                    .map(\.label).joined(separator: ", "))
        }
        .padding(20)
        .frame(width: Bench.width, height: Bench.height, alignment: .top)
    }
}

/// Treated as the key window without the app ever being activated: an
/// inactive app's window otherwise swallows the first click.
final class KeyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override var isKeyWindow: Bool { true }
}

final class FirstMouseHost<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor enum Bench {
    static let width: CGFloat = 480
    static let height: CGFloat = 320

    static func spin(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    static func event(_ type: NSEvent.EventType, at point: NSPoint, in window: NSWindow) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                           timestamp: ProcessInfo.processInfo.systemUptime,
                           windowNumber: window.windowNumber, context: nil,
                           eventNumber: 0, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1)!
    }

    static func run(metadataPath: String) {
        guard let data = FileManager.default.contents(atPath: metadataPath),
              let metadata = MediaMetadata.decode(from: data),
              let duration = metadata.duration else {
            print("Cannot read metadata at \(metadataPath)"); exit(1)
        }

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.finishLaunching()

        let start = 200.0, end = 400.0
        let parent = Parent(ranges: [ClipRange(start: start, end: end)], metadata: metadata)
        let host = FirstMouseHost(rootView: parent)
        let window = KeyWindow(
            contentRect: NSRect(x: -20000, y: -20000, width: width, height: height),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.orderBack(nil)
        window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        window.makeKey()

        // Storyboard sheets come from YouTube's image servers.
        spin(4)
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()

        // Geometry of the bar (TrimEditor: 12 pt padding, 44 pt bar,
        // 10 pt handles outside the track).
        let barX: CGFloat = 20 + 12, barTop: CGFloat = 20 + 12, handle: CGFloat = 10
        let track = width - 40 - 24 - handle * 2
        let endX = barX + handle + CGFloat(end / duration) * track + handle / 2
        let y = height - (barTop + 22)   // window coordinates start at the bottom

        if ProcessInfo.processInfo.environment["BENCH_DEBUG"] != nil {
            let probe = NSPoint(x: endX, y: y)
            print("hit at end handle:", host.hitTest(probe).map { String(describing: type(of: $0)) } ?? "nil",
                  "key:", window.isKeyWindow, "size:", host.frame.size)
        }

        let steps = 120, stepX: CGFloat = -1.5
        var times: [Double] = []
        Probe.parentBodies = 0

        window.sendEvent(event(.leftMouseDown, at: NSPoint(x: endX, y: y), in: window))
        for i in 1...steps {
            let t0 = DispatchTime.now().uptimeNanoseconds
            window.sendEvent(event(.leftMouseDragged,
                                   at: NSPoint(x: endX + CGFloat(i) * stepX, y: y), in: window))
            RunLoop.current.run(until: Date())
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            CATransaction.flush()
            times.append(Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000)
        }
        let duringDrag = Probe.parentBodies
        window.sendEvent(event(.leftMouseUp,
                               at: NSPoint(x: endX + CGFloat(steps) * stepX, y: y), in: window))
        spin(0.3)
        host.layoutSubtreeIfNeeded()

        let sorted = times.sorted()
        let mean = times.reduce(0, +) / Double(times.count)
        let p95 = sorted[Int(Double(sorted.count) * 0.95)]
        print(String(format: "events: %d  mean: %.2f ms  median: %.2f ms  p95: %.2f ms  max: %.2f ms",
                     steps, mean, sorted[sorted.count / 2], p95, sorted.last ?? 0))
        print("parent bodies during the drag: \(duringDrag)  after release: \(Probe.parentBodies)")
        print("range end after release: \(Probe.lastEnd.map(ClipRange.clock) ?? "?")"
              + "  (started at \(ClipRange.clock(end)))")
        exit(0)
    }
}

MainActor.assumeIsolated {
    Bench.run(metadataPath: CommandLine.arguments.dropFirst().first ?? "metadata.json")
}
