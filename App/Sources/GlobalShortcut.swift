import AppKit
import Carbon.HIToolbox

extension Notification.Name {
    /// The global shortcut was pressed, anywhere in the system.
    static let globalPasteAndDownload = Notification.Name("globalPasteAndDownload")
}

/// Global "paste and download" shortcut, customizable.
///
/// Goes through Carbon (`RegisterEventHotKey`) not a global event monitor:
/// the latter would require accessibility permission — an unsettling window
/// for what the app does. Carbon asks for none — and it cleanly rejects a
/// combo already taken by the system or another app, so we can tell the user.
@MainActor
enum GlobalShortcut {
    private static var hotKey: EventHotKeyRef?
    private static var handler: EventHandlerRef?

    /// Default combo: ⌥⌘V.
    static let defaultKeyCode = Int(kVK_ANSI_V)
    static let defaultModifiers = UInt(optionKey | cmdKey)
    static let defaultLabel = "⌥⌘V"

    /// Register the combo. Returns `false` if it's already taken —
    /// nothing is registered and the old one is lost.
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
            // The callback is a C function: go through a notification rather
            // than touch app state from this context.
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .globalPasteAndDownload, object: nil)
            }
            return noErr
        }, 1, &eventType, nil, &handler)
    }

    // MARK: - Translation from Keyboard Event

    /// Convert NSEvent modifiers to a Carbon modifier mask.
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt {
        var value: Int = 0
        if flags.contains(.command) { value |= cmdKey }
        if flags.contains(.option)  { value |= optionKey }
        if flags.contains(.control) { value |= controlKey }
        if flags.contains(.shift)   { value |= shiftKey }
        return UInt(value)
    }

    /// Readable label for a combo, in macOS menu order.
    static func label(flags: NSEvent.ModifierFlags, characters: String?) -> String {
        var text = ""
        if flags.contains(.control) { text += "⌃" }
        if flags.contains(.option)  { text += "⌥" }
        if flags.contains(.shift)   { text += "⇧" }
        if flags.contains(.command) { text += "⌘" }
        // The "unmodified" character: otherwise ⌥V would give "√".
        text += (characters ?? "").uppercased()
        return text
    }
}
