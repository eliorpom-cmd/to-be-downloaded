import AppKit
import Carbon.HIToolbox

extension Notification.Name {
    /// ⌥⌘V pressé n'importe où dans le système.
    static let globalPasteAndDownload = Notification.Name("globalPasteAndDownload")
}

/// Raccourci global ⌥⌘V : coller et télécharger depuis n'importe quelle app.
///
/// Passe par Carbon (`RegisterEventHotKey`) et NON par un moniteur d'événements
/// global : ce dernier exigerait l'autorisation d'accessibilité, c'est-à-dire
/// une fenêtre de permission inquiétante pour ce que fait l'app. Carbon n'en
/// demande aucune.
@MainActor
enum GlobalShortcut {
    private static var hotKey: EventHotKeyRef?
    private static var handler: EventHandlerRef?

    /// Libellé affiché dans les réglages.
    static let label = "⌥⌘V"

    static func setEnabled(_ enabled: Bool) {
        enabled ? register() : unregister()
    }

    private static func register() {
        guard hotKey == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            // Le callback est une fonction C : on repasse par une notification
            // plutôt que de toucher à l'état de l'app depuis ce contexte.
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .globalPasteAndDownload, object: nil)
            }
            return noErr
        }, 1, &eventType, nil, &handler)

        var id = EventHotKeyID(signature: OSType(0x444C_4452), id: 1)  // 'DLDR'
        RegisterEventHotKey(
            UInt32(kVK_ANSI_V),
            UInt32(optionKey | cmdKey),
            id,
            GetApplicationEventTarget(),
            0,
            &hotKey)
        _ = id
    }

    private static func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }
}
