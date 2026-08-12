// TBD — To Be Downloaded. Copyright (C) 2026 Elior Pommier.
// Licensed under the GNU AGPL v3 or later. See LICENSE and NOTICE.
//
// Retakes the screenshots the README and the website use.
//
// Run it through `scripts/screenshots.sh`, which explains the prerequisites
// and restores the desktop afterwards.
//
// It drives the real app through the accessibility API rather than by clicking
// at coordinates: a window that moves, a sidebar that gains an entry, a
// different screen size — none of it matters, because every step names the
// control it wants. The one thing it needs in exchange is permission, granted
// to whichever terminal runs it (System Settings ▸ Privacy & Security ▸
// Accessibility).
//
// It sets up no content. Whatever is in the Library is what the Library shot
// shows, and no download is started — a still window is a fine screenshot and
// waiting on the network would make this unrepeatable.

import AppKit
import ApplicationServices

// MARK: - Configuration

let bundleID = "com.byelior.tbd"

/// Window size for the shots that go in the repository: the window alone, no
/// desktop. 2× on a Retina display, so 1000 × 700 lands as 2000 × 1400.
let repoWindow = CGSize(width: 1000, height: 700)

/// Larger, for the website, where the window sits on the desktop with the
/// wallpaper showing around it. Close to the 2214 × 1584 already in place,
/// and clamped at capture time to whatever the screen can actually give.
let siteWindow = CGSize(width: 1060, height: 740)

/// Wallpaper kept around the window in the website shots, in points per side.
let siteMargin: CGFloat = 90

struct Shot {
    let destination: String
    /// Sidebar entry to select first, by its title.
    let route: String?
    let size: CGSize
    /// Include the desktop around the window.
    let withDesktop: Bool
}

// MARK: - Arguments

var repoDirectory = "docs/assets"
var siteDirectory = ("~/Documents/Code/tbd-site/public/media" as NSString).expandingTildeInPath
var doRepo = true, doSite = true

var arguments = Array(CommandLine.arguments.dropFirst())
while let argument = arguments.first {
    arguments.removeFirst()
    switch argument {
    case "--repo-only": doSite = false
    case "--site-only": doRepo = false
    case "--repo-dir": repoDirectory = arguments.removeFirst()
    case "--site-dir": siteDirectory = arguments.removeFirst()
    default:
        FileHandle.standardError.write(Data("unknown option \(argument)\n".utf8))
        exit(2)
    }
}

var shots: [Shot] = []
if doRepo {
    shots += [
        Shot(destination: "\(repoDirectory)/hero.png", route: "Download",
             size: repoWindow, withDesktop: false),
        Shot(destination: "\(repoDirectory)/library.png", route: "Library",
             size: repoWindow, withDesktop: false),
        Shot(destination: "\(repoDirectory)/network.png", route: "Remote Control",
             size: repoWindow, withDesktop: false),
    ]
}
if doSite, FileManager.default.fileExists(atPath: siteDirectory) {
    shots += [
        Shot(destination: "\(siteDirectory)/app-hero.png", route: "Download",
             size: siteWindow, withDesktop: true),
        Shot(destination: "\(siteDirectory)/private-settings.png", route: "Settings",
             size: siteWindow, withDesktop: true),
    ]
} else if doSite {
    print("· website folder not found, skipping its shots: \(siteDirectory)")
}

// MARK: - Accessibility

guard AXIsProcessTrusted() else {
    FileHandle.standardError.write(Data("""
        This needs Accessibility permission for the app running it (your
        terminal): System Settings ▸ Privacy & Security ▸ Accessibility.

        """.utf8))
    exit(1)
}

guard let app = NSRunningApplication
    .runningApplications(withBundleIdentifier: bundleID).first else {
    FileHandle.standardError.write(Data("\(bundleID) is not running.\n".utf8))
    exit(1)
}
let appElement = AXUIElementCreateApplication(app.processIdentifier)

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success
    else { return nil }
    return value
}

func children(_ element: AXUIElement) -> [AXUIElement] {
    attribute(element, kAXChildrenAttribute as String) as? [AXUIElement] ?? []
}

/// Everything a person would read on a control, joined, so one search matches
/// a title, a label, or a tooltip.
func label(_ element: AXUIElement) -> String {
    [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, kAXHelpAttribute]
        .compactMap { attribute(element, $0 as String) as? String }
        .joined(separator: " | ")
}

func pressable(under root: AXUIElement, depth: Int = 0) -> [AXUIElement] {
    guard depth < 40 else { return [] }
    var found: [AXUIElement] = []
    var actions: CFArray?
    if AXUIElementCopyActionNames(root, &actions) == .success,
       (actions as? [String])?.contains(kAXPressAction as String) == true {
        found.append(root)
    }
    for child in children(root) { found += pressable(under: child, depth: depth + 1) }
    return found
}

@discardableResult
func press(_ needle: String) -> Bool {
    let wanted = needle.lowercased()
    for element in pressable(under: appElement)
    where label(element).lowercased().contains(wanted) {
        return AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
    }
    return false
}

func mainWindow() -> AXUIElement? {
    (attribute(appElement, kAXWindowsAttribute as String) as? [AXUIElement])?.first
}

/// Put the window at a known size, centred on the main screen. Centred because
/// the website shots keep the desktop around it, and a window pushed against a
/// screen edge has wallpaper on three sides and a cliff on the fourth.
func place(_ requested: CGSize) -> CGRect? {
    guard let window = mainWindow(), let screen = NSScreen.main else { return nil }
    // AX coordinates start at the top-left of the main display; NSScreen's
    // start at the bottom-left. Only the height matters for the conversion,
    // and the menu bar is why the frame is not simply centred vertically.
    let visible = screen.visibleFrame

    // Never ask for more than the screen has left. The Dock is the usual
    // reason: it can leave under 780 points of height, and a window asked to
    // be taller than that is silently clamped — which then reads as "the
    // resize did not take" and burns the retries below for nothing.
    let size = CGSize(width: min(requested.width, visible.width - 40),
                      height: min(requested.height, visible.height - 40))
    let x = visible.midX - size.width / 2
    let topDown = screen.frame.height - visible.maxY
    let y = topDown + (visible.height - size.height) / 2

    var origin = CGPoint(x: x.rounded(), y: y.rounded())
    var wanted = size

    // Asked for repeatedly until it takes. One request is not enough: the
    // first shot of a run came out at the previous run's size, because macOS
    // restores a window's remembered frame around the moment the app is
    // activated and simply overwrote what had just been set. Setting it and
    // reading it back is the only version of this that is repeatable, which is
    // the entire reason for automating the shots.
    for attempt in 1...5 {
        if let value = AXValueCreate(.cgSize, &wanted) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
        }
        if let value = AXValueCreate(.cgPoint, &origin) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
        }
        usleep(400_000)
        guard let frame = currentFrame() else { continue }
        // Two points of tolerance: a window can refuse a size it cannot take,
        // and rounding is not worth a retry.
        if abs(frame.width - size.width) <= 2, abs(frame.height - size.height) <= 2 {
            return frame
        }
        if attempt == 5 {
            print("· window settled at \(Int(frame.width))×\(Int(frame.height)) "
                  + "instead of \(Int(size.width))×\(Int(size.height))")
            return frame
        }
    }
    return currentFrame()
}

/// What the window ACTUALLY became. A window has a minimum size and macOS may
/// nudge it; capturing the size we asked for would clip or pad the result.
func currentFrame() -> CGRect? {
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                          kCGNullWindowID) as? [[String: Any]] ?? []
    for info in list {
        guard info[kCGWindowOwnerPID as String] as? pid_t == app.processIdentifier,
              let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
              (bounds["Height"] ?? 0) > 300
        else { continue }
        return CGRect(x: bounds["X"] ?? 0, y: bounds["Y"] ?? 0,
                      width: bounds["Width"] ?? 0, height: bounds["Height"] ?? 0)
    }
    return nil
}

func windowNumber() -> Int? {
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                          kCGNullWindowID) as? [[String: Any]] ?? []
    for info in list {
        guard info[kCGWindowOwnerPID as String] as? pid_t == app.processIdentifier,
              let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
              (bounds["Height"] ?? 0) > 300
        else { continue }
        return info[kCGWindowNumber as String] as? Int
    }
    return nil
}

// MARK: - Capture

@discardableResult
func run(_ tool: String, _ arguments: [String]) -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: tool)
    process.arguments = arguments
    try? process.run()
    process.waitUntilExit()
    return process.terminationStatus
}

func capture(to path: String, frame: CGRect, withDesktop: Bool) {
    let url = URL(fileURLWithPath: path)
    try? FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

    if withDesktop {
        // A region, so the wallpaper shows around the window.
        //
        // Clamped to the screen's VISIBLE frame, not the whole display: the
        // difference is the menu bar and the Dock, and a Dock full of other
        // apps' icons at the bottom of a product shot is somebody's home
        // screen, not a picture of this app.
        let screen = NSScreen.main?.frame ?? .zero
        let visible = NSScreen.main?.visibleFrame ?? screen
        let usable = CGRect(x: visible.minX, y: screen.height - visible.maxY,
                            width: visible.width, height: visible.height)
        let region = frame.insetBy(dx: -siteMargin, dy: -siteMargin).intersection(usable)
        run("/usr/sbin/screencapture",
            ["-x", "-R\(Int(region.minX)),\(Int(region.minY)),"
                 + "\(Int(region.width)),\(Int(region.height))", path])
    } else {
        guard let number = windowNumber() else {
            print("· no window to capture for \(url.lastPathComponent)")
            return
        }
        // `-o` drops the drop shadow, which would otherwise bake a grey halo
        // into a PNG meant to sit on a white README.
        run("/usr/sbin/screencapture", ["-x", "-o", "-l\(number)", path])
    }
    let bytes = (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? Int ?? 0
    print("· \(path) (\(bytes / 1024) KB)")
}

// MARK: - Run

print("▶ Hiding everything else…")
for other in NSWorkspace.shared.runningApplications
where other.activationPolicy == .regular && other.bundleIdentifier != bundleID {
    other.hide()
}
app.activate()
usleep(900_000)

for shot in shots {
    if let route = shot.route, !press(route) {
        print("· could not select “\(route)”, skipping \(shot.destination)")
        continue
    }
    usleep(500_000)
    guard let frame = place(shot.size) else {
        print("· no window, skipping \(shot.destination)")
        continue
    }
    // A beat for the window to finish resizing and for any animation to
    // settle, or the shot catches the layout mid-flight.
    usleep(700_000)
    capture(to: shot.destination, frame: frame, withDesktop: shot.withDesktop)
}

print("""

Done. Two shots are not taken here and stay manual:
  · the menu bar item open (docs/assets/menubar.png, media/native-menubar.png)
    — a status item menu closes the moment anything else takes the focus
  · the web page on a phone (docs/assets/webui.png)
""")
