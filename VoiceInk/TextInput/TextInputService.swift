import Cocoa

final class TextInputService {
    func typeText(_ text: String) {
        guard AccessibilityHelper.isGranted else {
            print("Accessibility permission not granted - text not typed")
            return
        }

        DispatchQueue.main.async {
            let pasteboard = NSPasteboard.general
            let oldContents = pasteboard.string(forType: .string)

            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)

            // Simulate Cmd+V (V key = keycode 9)
            let source = CGEventSource(stateID: .combinedSessionState)

            if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
               let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) {
                keyDown.flags = .maskCommand
                keyUp.flags = .maskCommand

                keyDown.post(tap: .cghidEventTap)
                usleep(10000) // 10ms delay
                keyUp.post(tap: .cghidEventTap)
            }

            // Restore previous clipboard after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if let oldContents = oldContents {
                    pasteboard.clearContents()
                    pasteboard.setString(oldContents, forType: .string)
                }
            }
        }
    }
}
