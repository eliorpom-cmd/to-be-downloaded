// TBD — To Be Downloaded. Copyright (C) 2026 Elior Pommier.
// Licensed under the GNU AGPL v3 or later. See LICENSE and NOTICE.
//
// Shoots the Download screen with the Trim bar, without showing anything.
//
// The real `DownloadPane` of a Debug build (linked through `@testable
// import`) is hosted in a borderless window placed far off screen, at the
// size it has in the window next to the sidebar. Not `RootView`: its start-up
// task asks for notification permission and checks for updates. A link is typed
// into the real field, the real metadata comes from yt-dlp, and the handles
// are dragged with mouse events handed to the window directly: the cursor
// never moves and nothing comes to the front. Each state is written as a PNG.
//
// Usage: scripts/research/trim-shots/run.sh <output folder>

@testable import TBD
import SwiftUI
import AppKit

final class KeyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override var isKeyWindow: Bool { true }
}

final class FirstMouseHost<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor enum Shots {
    /// The detail area of the smallest window: 820 x 620, minus the 210 pt
    /// sidebar and its divider.
    static let size = CGSize(width: 609, height: 620)
    static let link = "https://www.youtube.com/watch?v=aqz-KE-bpKQ"

    static var window: KeyWindow!
    static var host: NSView!
    static var out = URL(fileURLWithPath: ".")

    static func spin(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    static func settle() {
        spin(0.4)
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
    }

    static func shoot(_ name: String) {
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        let rect = host.bounds
        guard let rep = host.bitmapImageRepForCachingDisplay(in: rect) else { return }
        host.cacheDisplay(in: rect, to: rep)
        let url = out.appendingPathComponent("\(name).png")
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        print("shot \(url.lastPathComponent) \(rep.pixelsWide)x\(rep.pixelsHigh)")
    }

    // MARK: Finding things

    static func views<T: NSView>(_ type: T.Type, in view: NSView) -> [T] {
        var found: [T] = []
        if let match = view as? T { found.append(match) }
        for child in view.subviews { found += views(type, in: child) }
        return found
    }

    /// Where the strip is, in window coordinates, read from the pixels of
    /// the whole-video state: the frame's top border is then the longest
    /// white line in the lower half of the pane, from 14 pt left of the
    /// strip to 14 pt right of it. (SwiftUI builds no accessibility tree
    /// without an assistive client, so the handles cannot be looked up.)
    struct Strip { let left: CGFloat; let width: CGFloat; let midY: CGFloat; let top: CGFloat }

    static func findStrip() -> Strip? {
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
        host.cacheDisplay(in: host.bounds, to: rep)
        let scale = CGFloat(rep.pixelsWide) / host.bounds.width
        var best: (y: Int, x: Int, length: Int) = (0, 0, 0)
        for y in (rep.pixelsHigh / 2)..<rep.pixelsHigh {
            var run = 0, runStart = 0
            for x in 0..<rep.pixelsWide {
                let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB)
                let white = (c?.redComponent ?? 0) > 0.92 && (c?.greenComponent ?? 0) > 0.92
                    && (c?.blueComponent ?? 0) > 0.92
                if white {
                    if run == 0 { runStart = x }
                    run += 1
                    if run > best.length { best = (y, runStart, run) }
                } else {
                    run = 0
                }
            }
        }
        guard CGFloat(best.length) / scale > 300 else { return nil }
        // The rounded corners shorten the border rows: read the edges on
        // the middle row instead, where the side borders are straight.
        let midRow = best.y + Int((TrimEditor.frameOverhang + TrimEditor.trackHeight / 2) * scale)
        func isWhite(_ x: Int) -> Bool {
            let c = rep.colorAt(x: x, y: midRow)?.usingColorSpace(.sRGB)
            return (c?.redComponent ?? 0) > 0.92 && (c?.greenComponent ?? 0) > 0.92
                && (c?.blueComponent ?? 0) > 0.92
        }
        guard let first = (0..<rep.pixelsWide).first(where: isWhite),
              let last = (0..<rep.pixelsWide).last(where: isWhite) else { return nil }
        let frameLeft = CGFloat(first) / scale
        let frameWidth = CGFloat(last + 1 - first) / scale
        let side = TrimEditor.handleWidth
        // Bitmap rows run from the top; the window's y from the bottom.
        let frameTop = host.bounds.height - CGFloat(best.y) / scale
        let stripTop = frameTop - TrimEditor.frameOverhang
        return Strip(left: frameLeft + side, width: frameWidth - side * 2,
                     midY: stripTop - TrimEditor.trackHeight / 2, top: stripTop)
    }

    /// Top of the frame, in window coordinates, read down the column `x`
    /// (a handle's): the white run as tall as the frame. The pane is
    /// centred, so it moves up and down as rows appear under the bar.
    static func frameTop(atX x: CGFloat) -> CGFloat? {
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
        host.cacheDisplay(in: host.bounds, to: rep)
        let scale = CGFloat(rep.pixelsWide) / host.bounds.width
        let column = Int(x * scale)
        let tall = (TrimEditor.trackHeight + TrimEditor.frameOverhang * 2) * scale
        var run = 0
        for y in 0..<rep.pixelsHigh {
            let c = rep.colorAt(x: column, y: y)?.usingColorSpace(.sRGB)
            if (c?.redComponent ?? 0) > 0.92, (c?.greenComponent ?? 0) > 0.92 {
                run += 1
            } else {
                if abs(CGFloat(run) - tall) <= 3 * scale {
                    return host.bounds.height - CGFloat(y - run) / scale
                }
                run = 0
            }
        }
        return nil
    }

    // MARK: Events

    static func mouse(_ type: NSEvent.EventType, _ point: NSPoint) {
        let event = NSEvent.mouseEvent(
            with: type, location: point, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0,
            clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1)!
        window.sendEvent(event)
        RunLoop.current.run(until: Date())
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
    }

    /// Drags a handle by `dx` points, in steps; leaves the button down when
    /// `release` is false, to shoot the drag itself.
    static func drag(from: NSPoint, by dx: CGFloat, release: Bool = true) {
        mouse(.leftMouseDown, from)
        let steps = 30
        for i in 1...steps {
            mouse(.leftMouseDragged, NSPoint(x: from.x + dx * CGFloat(i) / CGFloat(steps), y: from.y))
        }
        if release {
            mouse(.leftMouseUp, NSPoint(x: from.x + dx, y: from.y))
            settle()
        }
    }

    /// A click with a short hold: a button ignores a press released in the
    /// same pass of the run loop.
    static func click(_ point: NSPoint) {
        mouse(.leftMouseDown, point)
        spin(0.05)
        mouse(.leftMouseUp, point)
        settle()
    }

    // MARK: Run

    static func run() {
        out = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".", isDirectory: true)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.finishLaunching()
        app.appearance = NSAppearance(named: .darkAqua)

        // This tool's own defaults domain: past onboarding, nothing else.
        UserDefaults.standard.set(true, forKey: "onboardingCompleted")

        let library = LibraryStore()
        let manager = DownloadManager(library: library)
        let root = DownloadPane(manager: manager, settings: AppSettings.shared,
                                updater: EngineUpdater(), ffmpeg: FFmpegInstaller(),
                                library: library, goToLibrary: {})
            .tint(Theme.ink)
            .frame(width: size.width, height: size.height)
            .background(Theme.window)
        host = FirstMouseHost(rootView: root)
        window = KeyWindow(contentRect: NSRect(x: -20000, y: -20000, width: size.width, height: size.height),
                           styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        window.orderBack(nil)
        window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        window.makeKey()
        settle()

        // Type the link into the real field.
        guard let field = views(NSTextField.self, in: host).first(where: \.isEditable) else {
            print("no URL field"); exit(1)
        }
        window.makeFirstResponder(field)
        field.currentEditor()?.insertText(link)
        window.makeFirstResponder(nil)
        print("typed the link, waiting for yt-dlp and the storyboard…")
        var strip: Strip?
        for _ in 0..<240 {
            spin(0.5)
            if let found = findStrip() { strip = found; break }
        }
        guard let strip else { print("no Trim bar after 120 s"); shoot("timeout"); exit(1) }
        spin(4)     // storyboard sheets
        settle()
        shoot("1-whole-video")

        // Same range as the mockups: 1:00 to 1:10 of 10:35.
        let duration = 635.0, side = TrimEditor.handleWidth
        func x(_ t: Double) -> CGFloat { strip.left + CGFloat(t / duration) * strip.width }
        drag(from: NSPoint(x: x(0) - side / 2, y: strip.midY), by: x(60) - x(0))
        shoot("2-start-released")
        drag(from: NSPoint(x: x(duration) + side / 2, y: strip.midY), by: x(70) - x(duration),
             release: false)
        shoot("3-part-dragging")
        mouse(.leftMouseUp, NSPoint(x: x(70) + side / 2, y: strip.midY))
        settle()
        shoot("4-part-released")

        // The row under the bar: first chip on the left, Whole Video on the
        // right. Read down the start handle's column (at 1:00 now).
        func rowY() -> CGFloat {
            let top = frameTop(atX: x(60) - side / 2) ?? strip.top + TrimEditor.frameOverhang
            return top - TrimEditor.frameOverhang - TrimEditor.trackHeight - 10 - 12
        }
        click(NSPoint(x: strip.left - side + 30, y: rowY()))
        shoot("5-part-detail")
        click(NSPoint(x: strip.left + strip.width + side - 40, y: rowY()))
        spin(0.5)
        shoot("6-back-to-whole")
        exit(0)
    }
}

MainActor.assumeIsolated { Shots.run() }
