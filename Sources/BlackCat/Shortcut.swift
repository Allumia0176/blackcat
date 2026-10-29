import AppKit
import Carbon.HIToolbox

// Un raccourci clavier global : une touche et ses modificateurs.
struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt  // NSEvent.ModifierFlags.rawValue

    static let correctDefault = Shortcut(keyCode: UInt32(kVK_ANSI_C), modifiers: NSEvent.ModifierFlags([.control, .option]).rawValue)
    static let openDefault = Shortcut(keyCode: UInt32(kVK_ANSI_T), modifiers: NSEvent.ModifierFlags([.control, .option]).rawValue)
    static let closeDefault = Shortcut(keyCode: UInt32(kVK_Escape), modifiers: 0)

    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    var carbonModifiers: UInt32 {
        var m: UInt32 = 0
        if flags.contains(.control) { m |= UInt32(controlKey) }
        if flags.contains(.option) { m |= UInt32(optionKey) }
        if flags.contains(.shift) { m |= UInt32(shiftKey) }
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        return m
    }

    // « ⌃⌥ C », comme dans les maquettes.
    var display: String {
        var s = ""
        if flags.contains(.control) { s += "⌃" }
        if flags.contains(.option) { s += "⌥" }
        if flags.contains(.shift) { s += "⇧" }
        if flags.contains(.command) { s += "⌘" }
        return s.isEmpty ? Self.keyName(keyCode) : s + " " + Self.keyName(keyCode)
    }

    // Pour afficher le raccourci dans le menu de la barre.
    var keyEquivalent: String { Self.keyName(keyCode).count == 1 ? Self.keyName(keyCode).lowercased() : "" }

    init(keyCode: UInt32, modifiers: UInt) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    // Un raccourci global doit contenir ⌃, ⌥ ou ⌘.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection([.control, .option, .shift, .command])
        guard !flags.intersection([.control, .option, .command]).isEmpty else { return nil }
        self.init(keyCode: UInt32(event.keyCode), modifiers: flags.rawValue)
    }

    // Raccourci de la fenêtre (fermer) : une touche seule est permise, comme Échap.
    init(anyKey event: NSEvent) {
        let flags = event.modifierFlags.intersection([.control, .option, .shift, .command])
        self.init(keyCode: UInt32(event.keyCode), modifiers: flags.rawValue)
    }

    func matches(_ event: NSEvent) -> Bool {
        UInt32(event.keyCode) == keyCode
            && event.modifierFlags.intersection([.control, .option, .shift, .command]).rawValue == modifiers
    }

    private static let names: [Int: String] = [
        kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_Escape: "⎋",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12"
    ]

    // Nom de la touche selon le clavier de l'utilisateur (AZERTY compris).
    static func keyName(_ keyCode: UInt32) -> String {
        if Int(keyCode) == kVK_Space { return L("Space", "Espace") }
        if let name = names[Int(keyCode)] { return name }
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return "?" }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        var deadKeys: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = data.withUnsafeBytes { buffer -> OSStatus in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return -1 }
            return UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                  OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return "?" }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }
}
