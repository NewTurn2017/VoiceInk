import Cocoa

enum AccessibilityHelper {
    static var isGranted: Bool {
        AXIsProcessTrusted()
    }

    static func requestPermissionIfNeeded() {
        guard !AXIsProcessTrusted() else { return }

        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
        print("Accessibility permission required. Please enable VoiceInk in System Settings > Privacy & Security > Accessibility.")
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
