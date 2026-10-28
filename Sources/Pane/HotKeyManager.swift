import Carbon

final class HotKeyManager {
    struct Shortcut {
        let name: String
        let keyCode: UInt32
        let modifiers: UInt32
        let action: () -> Void

        init(name: String = "Shortcut", keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
            self.name = name
            self.keyCode = keyCode
            self.modifiers = modifiers
            self.action = action
        }
    }

    private var refs: [EventHotKeyRef?] = []
    private var actions: [UInt32: () -> Void] = [:]
    private var handler: EventHandlerRef?

    init() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr else { return status }
            let owner = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { owner.actions[id.id]?() }
            return noErr
        }, 1, &type, pointer, &handler)
    }

    @discardableResult
    func register(_ shortcuts: [Shortcut]) -> [String] {
        unregisterAll()
        var failures: [String] = []
        for (index, shortcut) in shortcuts.enumerated() {
            let idValue = UInt32(index + 1)
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: OSType(0x50_41_4E_45), id: idValue) // PANE
            if RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, id,
                                   GetApplicationEventTarget(), 0, &ref) == noErr {
                refs.append(ref)
                actions[idValue] = shortcut.action
            } else {
                failures.append(shortcut.name)
            }
        }
        return failures
    }

    func unregisterAll() {
        refs.compactMap { $0 }.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
        actions.removeAll()
    }

    deinit {
        unregisterAll()
        if let handler { RemoveEventHandler(handler) }
    }
}
