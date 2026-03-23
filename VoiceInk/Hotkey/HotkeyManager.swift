import Carbon
import Cocoa

final class HotkeyManager {
    var onHotkeyPressed: (() -> Void)?
    var onHotkeyReleased: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?

    init() {
        registerGlobalHotkey()
    }

    deinit {
        if let hotKeyRef = hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
    }

    private func registerGlobalHotkey() {
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(0x564F4943) // "VOIC"
        hotKeyID.id = 1

        // Opt + Space (kVK_Space = 49, optionKey = 0x0800)
        let status = RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if status != noErr {
            print("Failed to register hotkey: \(status)")
            return
        }

        // Register for both key press and release events
        var eventTypes = [
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            ),
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyReleased)
            )
        ]

        let handler: EventHandlerUPP = { _, event, userData -> OSStatus in
            guard let userData = userData, let event = event else {
                return OSStatus(eventNotHandledErr)
            }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            let eventKind = GetEventKind(event)

            DispatchQueue.main.async {
                if eventKind == UInt32(kEventHotKeyPressed) {
                    manager.onHotkeyPressed?()
                } else if eventKind == UInt32(kEventHotKeyReleased) {
                    manager.onHotkeyReleased?()
                }
            }
            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            2,
            &eventTypes,
            Unmanaged.passUnretained(self).toOpaque(),
            nil
        )
    }
}
