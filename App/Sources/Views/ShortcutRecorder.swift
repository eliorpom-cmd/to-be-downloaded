import SwiftUI
import AppKit

/// Champ d'enregistrement de raccourci, comme dans les Réglages Système :
/// on clique, on tape la combinaison, elle s'inscrit.
///
/// Un moniteur d'événements LOCAL suffit — on n'écoute que pendant que
/// l'utilisateur enregistre, et seulement dans cette app. Rien à voir avec le
/// raccourci global lui-même, qui passe par Carbon.
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
            // Échap annule sans rien changer.
            if event.keyCode == 53 { stop(); return nil }

            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            // Une touche seule ne fait pas un raccourci global : elle serait
            // capturée partout, y compris en pleine saisie de texte.
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
