import Carbon

/// Scorciatoie globali (funzionano da qualsiasi app, nessun permesso richiesto).
enum HotKeys {
    private static var handlers: [UInt32: () -> Void] = [:]
    private static var refs: [EventHotKeyRef?] = []
    private static var installed = false

    static let ctrlOpt = UInt32(controlKey | optionKey)

    static func register(_ id: UInt32, keyCode: Int, mods: UInt32 = ctrlOpt, _ handler: @escaping () -> Void) {
        installIfNeeded()
        handlers[id] = handler
        var ref: EventHotKeyRef?
        let hkID = EventHotKeyID(signature: OSType(0x50495044), id: id) // 'PIPD'
        RegisterEventHotKey(UInt32(keyCode), mods, hkID, GetApplicationEventTarget(), 0, &ref)
        refs.append(ref)
    }

    private static func installIfNeeded() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            DispatchQueue.main.async { HotKeys.handlers[hk.id]?() }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
