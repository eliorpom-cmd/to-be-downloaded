import AppKit
import Carbon.HIToolbox

extension Notification.Name {
    /// Le raccourci global a été pressé, n'importe où dans le système.
    static let globalPasteAndDownload = Notification.Name("globalPasteAndDownload")
}

/// Raccourci global « coller et télécharger », personnalisable.
///
/// Passe par Carbon (`RegisterEventHotKey`) et NON par un moniteur d'événements
/// global : ce dernier exigerait l'autorisation d'accessibilité, c'est-à-dire
/// une fenêtre de permission inquiétante pour ce que fait l'app. Carbon n'en
/// demande aucune — et il refuse proprement une combinaison déjà prise par le
/// système ou par une autre app, ce qui permet de le dire à l'utilisateur.
@MainActor
enum GlobalShortcut {
    private static var hotKey: EventHotKeyRef?
    private static var handler: EventHandlerRef?

    /// Combinaison par défaut : ⌥⌘V.
    static let defaultKeyCode = Int(kVK_ANSI_V)
    static let defaultModifiers = UInt(optionKey | cmdKey)
    static let defaultLabel = "⌥⌘V"

    /// Enregistre la combinaison. Renvoie `false` si elle est déjà prise —
    /// auquel cas rien n'est enregistré et l'ancienne est perdue.
    @discardableResult
    static func enable(keyCode: Int, modifiers: UInt) -> Bool {
        disable()
        installHandlerIfNeeded()

        let id = EventHotKeyID(signature: OSType(0x444C_4452), id: 1)  // 'DLDR'
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(keyCode), UInt32(modifiers), id, GetApplicationEventTarget(), 0, &reference)
        guard status == noErr, reference != nil else { return false }
        hotKey = reference
        return true
    }

    static func disable() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
    }

    private static func installHandlerIfNeeded() {
        guard handler == nil else { return }
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
    }

    // MARK: - Traduction depuis un événement clavier

    /// Convertit les modificateurs d'un `NSEvent` en masque Carbon.
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt {
        var value: Int = 0
        if flags.contains(.command) { value |= cmdKey }
        if flags.contains(.option)  { value |= optionKey }
        if flags.contains(.control) { value |= controlKey }
        if flags.contains(.shift)   { value |= shiftKey }
        return UInt(value)
    }

    /// Libellé lisible d'une combinaison, dans l'ordre des menus macOS.
    static func label(flags: NSEvent.ModifierFlags, characters: String?) -> String {
        var text = ""
        if flags.contains(.control) { text += "⌃" }
        if flags.contains(.option)  { text += "⌥" }
        if flags.contains(.shift)   { text += "⇧" }
        if flags.contains(.command) { text += "⌘" }
        // Le caractère « sans modificateurs » : sinon ⌥V donnerait « √ ».
        text += (characters ?? "").uppercased()
        return text
    }
}
