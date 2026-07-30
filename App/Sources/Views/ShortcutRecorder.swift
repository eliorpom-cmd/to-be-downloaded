import SwiftUI
import AppKit

/// Shortcut recording field, like in System Settings: click, type the
/// combo, it's recorded.
///
/// A LOCAL event monitor suffices — we only listen while the user records,
/// and only in this app. Nothing to do with the global shortcut itself, which
/// goes through Carbon.
struct ShortcutRecorder: View {
    @ObservedObject var settings: AppSettings

    @State private var recording = false
    @State private var monitor: Any?
    @State private var hovering = false

    var body: some View {
        Button(action: toggle) {
            Text(recording ? "Type a shortcut…" : settings.shortcutLabel)
                .font(Theme.Text.body)
                .monospaced()
                .foregroundStyle(recording ? Theme.labelSecondary : Theme.label)
                .frame(minWidth: 84)
                .frame(height: 24)
                .padding(.horizontal, Theme.Space.s10)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .fill(hovering && !recording ? Theme.fillSecondary : Theme.card)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                                .strokeBorder(recording ? Theme.focusRing : Theme.strokeControl,
                                              lineWidth: recording ? 2 : 1)
                        )
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(recording
              ? "Press the keys you want, or Escape to keep the current one"
              : "Click to change the shortcut")
        .onDisappear(perform: stop)
    }

    private func toggle() {
        recording ? stop() : start()
    }

    private func start() {
        settings.clearShortcutRejection()
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Escape cancels without changing anything.
            if event.keyCode == 53 { stop(); return nil }

            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            // A single key doesn't make a global shortcut: it would be
            // captured everywhere, even during text entry.
            guard !flags.intersection([.command, .option, .control]).isEmpty else {
                NSSound.beep()
                return nil
            }

            _ = settings.setShortcut(
                keyCode: Int(event.keyCode),
                modifiers: GlobalShortcut.carbonModifiers(from: flags),
                label: GlobalShortcut.label(
                    flags: flags, characters: event.charactersIgnoringModifiers))
            stop()
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
