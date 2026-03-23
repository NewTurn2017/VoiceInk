import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var currentStatus: STTStatus = .idle

    private var engine: STTEngine?
    private let hotkeyManager = HotkeyManager()
    private let textInputService = TextInputService()
    private let soundPlayer = SoundPlayer()
    private let keychainManager = KeychainManager.shared
    private let audioManager = AudioSessionManager()
    private var lastToggleTime: Date = .distantPast

    var menuBarIcon: String {
        switch currentStatus {
        case .idle: return "mic.slash"
        case .connecting: return "mic.badge.ellipsis"
        case .recording: return "mic.fill"
        case .error: return "mic.slash.fill"
        }
    }

    var isRecording: Bool {
        currentStatus == .recording
    }

    init() {
        keychainManager.migrateFromEnvironmentIfNeeded()
        setupEngine()
        setupHotkey()
        AccessibilityHelper.requestPermissionIfNeeded()
    }

    func toggleRecording() {
        let now = Date()
        guard now.timeIntervalSince(lastToggleTime) >= 0.5 else { return }
        lastToggleTime = now

        if isRecording {
            soundPlayer.play(.stop)
            engine?.stop()
        } else {
            soundPlayer.play(.start)
            engine?.start()
        }
    }

    // MARK: - Private

    private func setupEngine() {
        let cloud = CloudSTTEngine(keychainManager: keychainManager, audioManager: audioManager)
        cloud.onTranscript = { [weak self] text in
            self?.textInputService.typeText(text)
        }
        cloud.onStatusChange = { [weak self] status in
            Task { @MainActor in
                self?.currentStatus = status
            }
        }
        self.engine = cloud
    }

    private func setupHotkey() {
        hotkeyManager.onHotkeyPressed = { [weak self] in
            self?.toggleRecording()
        }
    }
}
