import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var currentStatus: STTStatus = .idle
    @Published var audioLevel: Float = 0
    @Published var showAlert = false
    @Published var alertMessage = ""

    /// Single source of truth for the model is UserDefaults["geminiModel"], written by
    /// the Settings @AppStorage picker. Read-only convenience for display.
    var geminiModel: GeminiModel {
        GeminiModel(rawValue: UserDefaults.standard.string(forKey: "geminiModel") ?? "") ?? .flash
    }

    private let keychainManager = KeychainManager.shared
    private let audioManager = AudioSessionManager()
    private let textInputService = TextInputService()
    private let soundPlayer = SoundPlayer()
    private let hotkeyManager = HotkeyManager()
    private let overlayController = RecordingOverlayController()
    private let resultModal = ResultModalController()
    let historyManager = TranscriptHistoryManager()
    private var controller: DictationController!

    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    var menuBarIcon: String {
        switch currentStatus {
        case .idle: return "mic.slash"
        case .recording: return "mic.fill"
        case .processing: return "ellipsis.circle"
        case .error: return "exclamationmark.triangle"
        }
    }

    var isRecording: Bool { currentStatus == .recording }

    init() {
        guard !AppState.isRunningTests else { return }

        let pipeline = GeminiPipeline(
            apiKeyProvider: { [keychainManager] in keychainManager.getAPIKey(for: .gemini) },
            model: { GeminiModel(rawValue: UserDefaults.standard.string(forKey: "geminiModel") ?? "") ?? .flash }
        )
        let controller = DictationController(
            audioManager: audioManager,
            pipeline: pipeline,
            textInput: textInputService,
            history: historyManager,
            resultModal: resultModal
        )
        controller.hasAPIKey = { [keychainManager] in keychainManager.hasAPIKey(for: .gemini) }
        controller.onStatusChange = { [weak self] status in
            Task { @MainActor in
                self?.currentStatus = status
                if status == .idle { self?.audioLevel = 0 }
                self?.updateOverlay(for: status)
                if case .error = status { self?.soundPlayer.play(.stop) }
            }
        }
        controller.onAudioLevel = { [weak self] level in
            Task { @MainActor in self?.audioLevel = level }
        }
        controller.onError = { [weak self] title, message in
            Task { @MainActor in self?.showErrorAlert(title: title, message: message) }
        }
        self.controller = controller

        hotkeyManager.onHotkey = { [weak self] mode in
            self?.handleHotkey(mode)
        }

        AccessibilityHelper.requestPermissionIfNeeded()
    }

    func toggle(mode: DictationMode = .cleanup) {
        handleHotkey(mode)
    }

    private func handleHotkey(_ mode: DictationMode) {
        if controller.isRecording {
            soundPlayer.play(.stop)
        } else if currentStatus == .idle {
            soundPlayer.play(.start)
        }
        controller.toggle(mode: mode)
    }

    private func updateOverlay(for status: STTStatus) {
        switch status {
        case .recording, .processing:
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
        if alert.runModal() == .alertFirstButtonReturn {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
    }
}
