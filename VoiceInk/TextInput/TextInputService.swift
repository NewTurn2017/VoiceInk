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
        if focusedElementIsEditable() {
            paste(text)
            return .pasted
        }
        copyToClipboard(text)
        return .copiedToClipboard
    }

    // MARK: - Private

    private func focusedElementIsEditable() -> Bool {
        let system = AXUIElementCreateSystemWide()
        var focused: AnyObject?
        let err = AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused)
        guard err == .success, let focused = focused else { return false }
        let element = focused as! AXUIElement

        var roleValue: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
        if Self.isEditableRole(roleValue as? String) { return true }

        var settable: DarwinBoolean = false
        AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable)
        return settable.boolValue
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
