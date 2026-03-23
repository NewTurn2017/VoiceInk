import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var currentStatus: STTStatus = .idle
    @Published var engineType: STTEngineType {
        didSet { UserDefaults.standard.set(engineType.rawValue, forKey: "sttEngineType") }
    }
    @Published var modelSize: STTModelSize {
        didSet { UserDefaults.standard.set(modelSize.rawValue, forKey: "sttModelSize") }
    }
    @Published var modelDownloadProgress: Double?

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
        // Restore saved preferences
        let savedEngine = UserDefaults.standard.string(forKey: "sttEngineType") ?? STTEngineType.local.rawValue
        self.engineType = STTEngineType(rawValue: savedEngine) ?? .local

        let savedModel = UserDefaults.standard.string(forKey: "sttModelSize") ?? STTModelSize.small.rawValue
        self.modelSize = STTModelSize(rawValue: savedModel) ?? .small

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

    func switchEngine(to type: STTEngineType) {
        guard type != engineType || engine == nil else { return }

        // Stop current engine if recording
        if isRecording {
            engine?.stop()
        }

        engineType = type
        setupEngine()
    }

    func switchModel(to size: STTModelSize) {
        guard size != modelSize else { return }

        if isRecording {
            engine?.stop()
        }

        modelSize = size

        // Rebuild local engine with new model
        if engineType == .local {
            setupEngine()
        }
    }

    // MARK: - Private

    private func setupEngine() {
        // Detach old engine callbacks
        engine?.onTranscript = nil
        engine?.onStatusChange = nil

        switch engineType {
        case .local:
            let local = LocalSTTEngine(audioManager: audioManager, modelId: modelSize.rawValue)
            local.onModelProgress = { [weak self] progress, status in
                Task { @MainActor in
                    self?.modelDownloadProgress = progress < 1.0 ? progress : nil
                }
            }
            connectEngine(local)

        case .cloud:
            let cloud = CloudSTTEngine(keychainManager: keychainManager, audioManager: audioManager)
            connectEngine(cloud)
        }
    }

    private func connectEngine(_ newEngine: STTEngine) {
        newEngine.onTranscript = { [weak self] text in
            self?.textInputService.typeText(text)
        }
        newEngine.onStatusChange = { [weak self] status in
            Task { @MainActor in
                self?.currentStatus = status
            }
        }
        self.engine = newEngine
    }

    private func setupHotkey() {
        hotkeyManager.onHotkeyPressed = { [weak self] in
            self?.toggleRecording()
        }
    }
}
