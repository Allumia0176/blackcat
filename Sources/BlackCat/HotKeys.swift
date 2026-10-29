import Carbon.HIToolbox

// Raccourcis globaux via Carbon : ils marchent depuis n'importe quelle app
// et ne demandent aucune autorisation.
@MainActor
enum HotKeys {
    enum Action: UInt32 { case correct = 1, open = 2 }

    private static var refs: [Action: EventHotKeyRef] = [:]
    private static var handlers: [Action: () -> Void] = [:]
    private static var installed = false

    static func register(_ action: Action, _ shortcut: Shortcut?, handler: @escaping () -> Void) {
        installIfNeeded()
        if let ref = refs.removeValue(forKey: action) { UnregisterEventHotKey(ref) }
        handlers[action] = handler
        guard let shortcut else { return }
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x48544850), id: action.rawValue)  // « HTHP »
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.carbonModifiers, id, GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref { refs[action] = ref }
    }

    // Pendant qu'on enregistre un nouveau raccourci, les anciens ne doivent pas se déclencher.
    static func suspend(_ suspended: Bool) { paused = suspended }
    static var isRecording: Bool { paused }
    private static var paused = false

    private static func installIfNeeded() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            MainActor.assumeIsolated {
                guard !HotKeys.paused, let action = HotKeys.Action(rawValue: id.id) else { return }
                HotKeys.handlers[action]?()
            }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
