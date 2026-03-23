import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var currentStatus: STTStatus = .idle
    @Published var audioLevel: Float = 0
    @Published var modelDownloadProgress: Double?
    @Published var showAlert = false
    @Published var alertMessage = ""

    @Published var holdToTalk: Bool {
        didSet {
            guard oldValue != holdToTalk else { return }
            UserDefaults.standard.set(holdToTalk, forKey: "holdToTalk")
        }
    }

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
    private let overlayController = RecordingOverlayController()
    let historyManager = TranscriptHistoryManager()

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
        self.holdToTalk = UserDefaults.standard.bool(forKey: "holdToTalk")

        let savedEngine = UserDefaults.standard.string(forKey: "sttEngineType") ?? STTEngineType.local.rawValue
        self.engineType = STTEngineType(rawValue: savedEngine) ?? .local

        let savedModel = UserDefaults.standard.string(forKey: "sttModelSize") ?? STTModelSize.small.rawValue
        self.modelSize = STTModelSize(rawValue: savedModel) ?? .small

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
            stopRecordingAction()
        } else {
            startRecordingAction()
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
            guard let self = self else { return }
            self.textInputService.typeText(text)
            self.historyManager.add(
                text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                engineType: self.engineType.displayName
            )
        }
        newEngine.onStatusChange = { [weak self] status in
            Task { @MainActor in
                self?.currentStatus = status
                if status == .idle {
                    self?.audioLevel = 0
                }
                self?.updateOverlay(for: status)
            }
        }
        newEngine.onAudioLevel = { [weak self] level in
            Task { @MainActor in
                self?.audioLevel = level
            }
        }
        self.engine = newEngine
    }

    private func updateOverlay(for status: STTStatus) {
        switch status {
        case .connecting, .recording:
            overlayController.show(appState: self)
        case .idle, .error:
            overlayController.dismiss()
        }
    }

    private func showErrorAlert(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "OK")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // Open Settings to API Keys tab
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
    }

    private func setupHotkey() {
        hotkeyManager.onHotkeyPressed = { [weak self] in
            guard let self = self else { return }
            if self.holdToTalk {
                // Hold mode: press = start recording
                if !self.isRecording {
                    self.startRecordingAction()
                }
            } else {
                // Toggle mode: press = toggle
                self.toggleRecording()
            }
        }
        hotkeyManager.onHotkeyReleased = { [weak self] in
            guard let self = self else { return }
            if self.holdToTalk && self.isRecording {
                // Hold mode: release = stop recording
                self.stopRecordingAction()
            }
        }
    }

    private func startRecordingAction() {
        // Pre-check: Cloud engine requires API key
        if engineType == .cloud && !keychainManager.hasAPIKey(for: .elevenLabs) {
            showErrorAlert(
                title: "API Key Required",
                message: "ElevenLabs API key is required for Cloud engine.\nGo to Settings > API Keys to add your key."
            )
            return
        }
        soundPlayer.play(.start)
        engine?.start()
    }

    private func stopRecordingAction() {
        soundPlayer.play(.stop)
        engine?.stop()
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

            let newHoldToTalk = UserDefaults.standard.bool(forKey: "holdToTalk")
            if newHoldToTalk != self.holdToTalk {
                self.holdToTalk = newHoldToTalk
            }
        }
    }
}
