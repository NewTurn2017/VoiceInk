import Cocoa
import Carbon
import AudioToolbox

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var sttManager: STTManager!
    private var isRecording = false
    private var eventHandler: EventHandlerRef?
    private var lastToggleTime: Date = Date.distantPast
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("🚀 VoiceType starting...")
        
        // Hide dock icon (background app)
        NSApp.setActivationPolicy(.accessory)
        
        // Setup menu bar
        setupStatusBar()
        print("✅ Status bar setup complete")
        
        // Setup STT Manager
        sttManager = STTManager()
        sttManager.onTranscript = { [weak self] text in
            self?.typeText(text)
        }
        sttManager.onStatusChange = { [weak self] status in
            DispatchQueue.main.async {
                self?.updateStatusIcon(status)
                // Sync isRecording state
                if status == .idle || status == .error {
                    self?.isRecording = false
                } else if status == .recording {
                    self?.isRecording = true
                }
            }
        }
        print("✅ STT Manager setup complete")
        
        // Register global hotkey (Opt + Space)
        registerGlobalHotkey()
        print("✅ Hotkey registered")
        
        // Request accessibility permission
        requestAccessibilityPermission()
        print("✅ VoiceType ready! Press ⌥+Space to toggle recording")
    }
    
    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        if let button = statusItem.button {
            // Use text fallback if SF Symbol not available
            if let image = NSImage(systemSymbolName: "mic.slash", accessibilityDescription: "Voice Type") {
                button.image = image
            } else {
                button.title = "🎤"
            }
        }
        
        let menu = NSMenu()
        
        let infoItem = NSMenuItem(title: "⌥ Space로 녹음 토글", action: nil, keyEquivalent: "")
        infoItem.isEnabled = false
        menu.addItem(infoItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "종료", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem.menu = menu
    }
    
    private func updateStatusIcon(_ status: STTStatus) {
        guard let button = statusItem.button else { return }
        
        switch status {
        case .idle:
            if let img = NSImage(systemSymbolName: "mic.slash", accessibilityDescription: "Idle") {
                button.image = img
            } else {
                button.title = "🎤"
            }
        case .connecting:
            if let img = NSImage(systemSymbolName: "mic.badge.ellipsis", accessibilityDescription: "Connecting") {
                button.image = img
            } else {
                button.title = "⏳"
            }
        case .recording:
            if let img = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Recording") {
                button.image = img
            } else {
                button.title = "🔴"
            }
        case .error:
            if let img = NSImage(systemSymbolName: "mic.slash.fill", accessibilityDescription: "Error") {
                button.image = img
            } else {
                button.title = "❌"
            }
        }
        print("Status: \(status)")
    }
    
    private func registerGlobalHotkey() {
        // Using Carbon for global hotkey
        var hotKeyRef: EventHotKeyRef?
        var gMyHotKeyID = EventHotKeyID()
        gMyHotKeyID.signature = OSType(0x564F4943) // "VOIC"
        gMyHotKeyID.id = 1
        
        // Opt + Space (kVK_Space = 49, optionKey = 0x0800)
        let status = RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(optionKey),
            gMyHotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        
        if status != noErr {
            print("Failed to register hotkey: \(status)")
            return
        }
        
        // Install event handler
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        
        let handler: EventHandlerUPP = { _, event, userData -> OSStatus in
            guard let userData = userData else { return OSStatus(eventNotHandledErr) }
            let appDelegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
            appDelegate.toggleRecording()
            return noErr
        }
        
        InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            nil
        )
    }
    
    private func requestAccessibilityPermission() {
        // Check without prompting first
        if AXIsProcessTrusted() {
            print("✅ Accessibility permission granted")
            return
        }
        
        // Only prompt once at startup
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
        print("⚠️ 접근성 권한이 필요합니다. 시스템 설정 > 개인정보 보호 및 보안 > 손쉬운 사용에서 VoiceType을 허용해주세요.")
    }
    
    @objc private func toggleRecording() {
        // Debounce: ignore if called within 500ms
        let now = Date()
        if now.timeIntervalSince(lastToggleTime) < 0.5 {
            print("⏭️ Debounced toggle")
            return
        }
        lastToggleTime = now
        
        print("🔄 Toggle called, isRecording: \(isRecording)")
        
        if isRecording {
            // Stop recording
            playSound(start: false)
            sttManager.stopRecording()
            print("🛑 Recording stopped")
        } else {
            // Start recording
            playSound(start: true)
            sttManager.startRecording()
            print("🎙️ Recording started")
        }
    }
    
    private func playSound(start: Bool) {
        // macOS system sounds: Basso, Blow, Bottle, Frog, Funk, Glass, Hero, Morse, Ping, Pop, Purr, Sosumi, Submarine, Tink
        if start {
            // 시작: 높은 음 (Pop - 팝 소리)
            if let sound = NSSound(named: "Pop") {
                sound.play()
            } else if let sound = NSSound(named: "Tink") {
                sound.play()
            } else {
                NSSound.beep()
            }
        } else {
            // 종료: 낮은 음 (Basso - 낮은 베이스 소리)
            if let sound = NSSound(named: "Basso") {
                sound.play()
            } else if let sound = NSSound(named: "Funk") {
                sound.play()
            } else {
                NSSound.beep()
            }
        }
    }
    
    private func typeText(_ text: String) {
        print("⌨️ Typing: \(text)")
        
        // Check accessibility permission without prompting
        guard AXIsProcessTrusted() else {
            print("❌ Accessibility permission not granted - text not typed")
            return
        }
        
        // Use clipboard + paste method for better compatibility with all apps
        DispatchQueue.main.async {
            // Save current clipboard
            let pasteboard = NSPasteboard.general
            let oldContents = pasteboard.string(forType: .string)
            
            // Set new text to clipboard
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            
            // Simulate Cmd+V to paste
            let source = CGEventSource(stateID: .combinedSessionState)
            
            // Key down: Cmd + V (V key = keycode 9)
            if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
               let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) {
                keyDown.flags = .maskCommand
                keyUp.flags = .maskCommand
                
                keyDown.post(tap: .cghidEventTap)
                usleep(10000) // 10ms delay
                keyUp.post(tap: .cghidEventTap)
            }
            
            // Restore old clipboard after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if let oldContents = oldContents {
                    pasteboard.clearContents()
                    pasteboard.setString(oldContents, forType: .string)
                }
            }
            
            print("✅ Pasted: \(text)")
        }
    }
    
    @objc private func quit() {
        sttManager.stopRecording()
        NSApp.terminate(nil)
    }
}
