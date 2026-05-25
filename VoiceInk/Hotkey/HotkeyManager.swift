import Carbon
import Cocoa

final class HotkeyManager {
    /// Called on the main thread when a registered hotkey fires.
    var onHotkey: ((DictationMode) -> Void)?

    private struct Binding {
        let id: UInt32
        let keyCode: UInt32
        let modifiers: UInt32
        let mode: DictationMode
    }

    private let bindings: [Binding] = [
        Binding(id: 1, keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey), mode: .cleanup),
        Binding(id: 2, keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey | shiftKey), mode: .translateToEnglish)
    ]

    private var refs: [EventHotKeyRef?] = []
    private var idToMode: [UInt32: DictationMode] = [:]
    private var handlerRef: EventHandlerRef?

    init() {
        register()
    }

    deinit {
        refs.forEach { if let r = $0 { UnregisterEventHotKey(r) } }
        if let h = handlerRef { RemoveEventHandler(h) }
    }

    private func register() {
        let signature = OSType(0x564F4943) // "VOIC"
        for b in bindings {
            let hotKeyID = EventHotKeyID(signature: signature, id: b.id)
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(b.keyCode, b.modifiers, hotKeyID,
                                             GetApplicationEventTarget(), 0, &ref)
            if status == noErr {
                refs.append(ref)
                idToMode[b.id] = b.mode
            } else {
                print("Failed to register hotkey \(b.id): \(status)")
            }
        }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))

        let handler: EventHandlerUPP = { _, event, userData -> OSStatus in
            guard let userData = userData, let event = event else {
                return OSStatus(eventNotHandledErr)
            }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()

            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hkID)

            if let mode = manager.idToMode[hkID.id] {
                DispatchQueue.main.async { manager.onHotkey?(mode) }
            }
            return noErr
        }

        InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType,
                            Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
    }
}
