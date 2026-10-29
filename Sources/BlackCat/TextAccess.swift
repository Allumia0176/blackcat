import AppKit
import ApplicationServices
import Carbon.HIToolbox

// Le texte sélectionné dans l'app au premier plan.
struct Grab {
    let text: String
    let element: AXUIElement?
    let range: CFRange?   // position dans le champ, quand l'app la donne
    let bounds: CGRect?   // place à l'écran (coordonnées AppKit), quand l'app la donne
}

// Lecture et remplacement du texte sélectionné, dans n'importe quelle app.
// Les apps d'Apple répondent à l'Accessibilité ; pour les autres, on passe
// par ⌘C / ⌘V en remettant ensuite le presse-papiers comme il était.
@MainActor
enum TextAccess {
    static func selection() async -> Grab? {
        let element = focusedElement()
        var text: String?
        var range: CFRange?
        var emptySelection = false
        if let element {
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &value) == .success,
               let selected = value as? String, !selected.isEmpty {
                text = selected
            }
            var rangeValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeValue) == .success,
               let rangeValue, CFGetTypeID(rangeValue) == AXValueGetTypeID() {
                var r = CFRange()
                if AXValueGetValue(rangeValue as! AXValue, .cfRange, &r) {
                    if r.length > 0 { range = r } else { emptySelection = true }
                }
            }
        }
        // Rien de sélectionné, et l'app le dit : surtout pas de ⌘C, qui copierait
        // toute la ligne dans certaines apps (VS Code) et la dupliquerait au collage.
        if text == nil && emptySelection { return nil }
        if text == nil { text = await copySelection() }
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        // La position n'est fiable que si elle correspond bien au texte lu.
        if let r = range, r.length != (text as NSString).length { range = nil }
        let bounds = range.flatMap { r in element.flatMap { bounds(of: r, in: $0) } }
        return Grab(text: text, element: element, range: range, bounds: bounds)
    }

    static func focusedElement() -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    // Place à l'écran d'un morceau de texte, convertie en coordonnées AppKit.
    static func bounds(of range: CFRange, in element: AXUIElement) -> CGRect? {
        var r = range
        guard let value = AXValueCreate(.cfRange, &r) else { return nil }
        var out: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, value, &out) == .success,
              let out, CFGetTypeID(out) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(out as! AXValue, .cgRect, &rect), rect.width > 0, rect.height > 0 else { return nil }
        let top = NSScreen.screens.first?.frame.maxY ?? 0  // l'Accessibilité compte depuis le haut de l'écran principal
        let converted = CGRect(x: rect.minX, y: top - rect.maxY, width: rect.width, height: rect.height)
        guard NSScreen.screens.contains(where: { $0.frame.intersects(converted) }) else { return nil }
        return converted
    }

    // Remise du presse-papiers en cours : une nouvelle correction l'attend avant de s'en servir.
    private static var pendingRestore: Task<Void, Never>?

    // Le texte actuellement à cette position dans le champ (pour savoir si un mot corrigé est toujours là).
    static func string(of range: CFRange, in element: AXUIElement) -> String? {
        var r = range
        guard let value = AXValueCreate(.cfRange, &r) else { return nil }
        var out: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute as CFString, value, &out) == .success else { return nil }
        return out as? String
    }

    static func replaceSelection(with text: String) async {
        await pendingRestore?.value
        let pasteboard = NSPasteboard.general
        let saved = snapshot(pasteboard)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        // Marque « éphémère » : les gestionnaires de presse-papiers ne l'enregistrent pas.
        pasteboard.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        await waitForModifiersRelease()
        press(kVK_ANSI_V)
        try? await Task.sleep(for: .milliseconds(150))  // le temps que l'app colle, avant les soulignés
        // Le presse-papiers est remis en fond, sans retarder l'affichage (une app lente peut
        // lire le collage tard : on lui laisse 0,8 s en tout).
        pendingRestore = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(650))
            restore(saved, to: pasteboard)
            pendingRestore = nil
        }
    }

    private static func copySelection() async -> String? {
        await pendingRestore?.value
        let pasteboard = NSPasteboard.general
        let saved = snapshot(pasteboard)
        let before = pasteboard.changeCount
        await waitForModifiersRelease()
        press(kVK_ANSI_C)
        for _ in 0..<30 where pasteboard.changeCount == before {
            try? await Task.sleep(for: .milliseconds(10))
        }
        let text = pasteboard.changeCount != before ? pasteboard.string(forType: .string) : nil
        restore(saved, to: pasteboard)
        return text
    }

    // ⌃⌥ encore enfoncées transformeraient ⌘C en ⌃⌥⌘C : on attend qu'elles soient relâchées.
    private static func waitForModifiersRelease() async {
        for _ in 0..<50 {
            let flags = CGEventSource.flagsState(.combinedSessionState)
            if flags.intersection([.maskControl, .maskAlternate, .maskCommand, .maskShift]).isEmpty { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private static func press(_ key: Int) {
        let source = CGEventSource(stateID: .combinedSessionState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(key), keyDown: down)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }

    private static func snapshot(_ pasteboard: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        (pasteboard.pasteboardItems ?? []).map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in item.data(forType: type).map { (type, $0) } })
        }
    }

    private static func restore(_ saved: [[NSPasteboard.PasteboardType: Data]], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let items = saved.map { entries -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in entries { item.setData(data, forType: type) }
            return item
        }
        if !items.isEmpty { pasteboard.writeObjects(items) }
    }
}
