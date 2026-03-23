import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var currentStatus: STTStatus = .idle
    @Published var modelDownloadProgress: Double?

    @Published var engineType: STTEngineType {
        didSet {
            guard oldValue != engineType else { return }
            UserDefaults.standard.set(engineType.rawValue, forKey: "sttEngineType")
            rebuildEngine()
        }
    }

    @Published var modelSize: STTModelSize {
        didSet {
            guard oldValue != modelSize else { return }
            UserDefaults.standard.set(modelSize.rawValue, forKey: "sttModelSize")
            if engineType == .local {
                rebuildEngine()
            }
        }
    }

    private var engine: STTEngine?
    private let hotkeyManager = HotkeyManager()
    private let textInputService = TextInputService()
    private let soundPlayer = SoundPlayer()
    private let keychainManager = KeychainManager.shared
    private let audioManager = AudioSessionManager()
    private var lastToggleTime: Date = .distantPast
    private var settingsObserver: NSObjectProtocol?

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
        let savedEngine = UserDefaults.standard.string(forKey: "sttEngineType") ?? STTEngineType.local.rawValue
        self.engineType = STTEngineType(rawValue: savedEngine) ?? .local

        let savedModel = UserDefaults.standard.string(forKey: "sttModelSize") ?? STTModelSize.small.rawValue
        self.modelSize = STTModelSize(rawValue: savedModel) ?? .small

        keychainManager.migrateFromEnvironmentIfNeeded()
        setupEngine()
        setupHotkey()
        observeSettingsChanges()
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

    private func rebuildEngine() {
        if isRecording {
            engine?.stop()
        }
        setupEngine()
    }

    private func setupEngine() {
        engine?.onTranscript = nil
        engine?.onStatusChange = nil

        switch engineType {
        case .local:
            let local = LocalSTTEngine(audioManager: audioManager, modelId: modelSize.rawValue)
            local.onModelProgress = { [weak self] progress, _ in
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

    /// Observe UserDefaults changes from Settings window (@AppStorage writes)
    private func observeSettingsChanges() {
        settingsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            let newEngineRaw = UserDefaults.standard.string(forKey: "sttEngineType") ?? STTEngineType.local.rawValue
            let newModelRaw = UserDefaults.standard.string(forKey: "sttModelSize") ?? STTModelSize.small.rawValue

            if let newEngine = STTEngineType(rawValue: newEngineRaw), newEngine != self.engineType {
                self.engineType = newEngine
            }
            if let newModel = STTModelSize(rawValue: newModelRaw), newModel != self.modelSize {
                self.modelSize = newModel
            }
        }
    }
}
