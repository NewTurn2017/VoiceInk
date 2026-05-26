import Cocoa
import ApplicationServices

enum InsertResult: Equatable {
    case pasted
    case copiedToClipboard
}

final class TextInputService {

    /// Pure helper — is this AX role an editable text element?
    static func isEditableRole(_ role: String?) -> Bool {
        guard let role = role else { return false }
        return [
            kAXTextFieldRole as String,
            kAXTextAreaRole as String,
            kAXComboBoxRole as String
        ].contains(role)
    }

    /// Inserts text at the focused editable element, or copies to clipboard if none.
    /// Must be called on the main thread.
    @discardableResult
    func insert(_ text: String) -> InsertResult {
        guard AccessibilityHelper.isGranted else {
            copyToClipboard(text)
            return .copiedToClipboard
        }
        // Paste-first: if any app element is focused, synthesize ⌘V so the text lands
        // at the cursor. This works even in GPU/Electron apps (terminals, VS Code,
        // browsers) that don't expose a standard editable AX role. The clipboard modal
        // is reserved for "nothing is focused" (e.g. the Finder desktop).
        if hasFocusedElement() {
            paste(text)
            return .pasted
        }
        copyToClipboard(text)
        return .copiedToClipboard
    }

    // MARK: - Private

    /// True when some app currently owns a focused UI element (i.e. there's a place
    /// for a ⌘V paste to land). False on the bare desktop / when nothing is focused.
    private func hasFocusedElement() -> Bool {
        let system = AXUIElementCreateSystemWide()
        var focused: AnyObject?
        let err = AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused)
        guard err == .success, let focused = focused else { return false }
        return CFGetTypeID(focused) == AXUIElementGetTypeID()
    }

    private func paste(_ text: String) {
        let pasteboard = NSPasteboard.general
        let old = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        pasteboard.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))

        let source = CGEventSource(stateID: .combinedSessionState)
        if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
           let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) {
            keyDown.flags = .maskCommand
            keyUp.flags = .maskCommand
            keyDown.post(tap: .cghidEventTap)
            usleep(10000)
            keyUp.post(tap: .cghidEventTap)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            if let old = old {
                pasteboard.clearContents()
                pasteboard.setString(old, forType: .string)
            }
        }
    }

    /// Leaves result on the clipboard for the user to paste manually (no restore).
    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
