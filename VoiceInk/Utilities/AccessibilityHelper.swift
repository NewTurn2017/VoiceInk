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
}
