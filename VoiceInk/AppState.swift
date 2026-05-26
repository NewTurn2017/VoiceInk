import AppKit
import AVFoundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var currentStatus: STTStatus = .idle
    @Published var audioLevel: Float = 0
    @Published var showAlert = false
    @Published var alertMessage = ""
    @Published var accessibilityGranted = false
    @Published var microphoneGranted = false

    /// Single source of truth for the model is UserDefaults["geminiModel"], written by
    /// the Settings @AppStorage picker. Read-only convenience for display.
    var geminiModel: GeminiModel { GeminiModel.current }

    private let keychainManager = KeychainManager.shared
    private let audioManager = AudioSessionManager()
    private let textInputService = TextInputService()
    private let soundPlayer = SoundPlayer()
    private let hotkeyManager = HotkeyManager()
    private let overlayController = RecordingOverlayController()
    private let resultModal = ResultModalController()
    let historyManager = TranscriptHistoryManager()
    private var controller: DictationController!
    private var accessibilityTimer: Timer?

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
            model: { GeminiModel.current }
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
        refreshPermissions()
        observePermissions()
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

    // MARK: - Permissions (Accessibility + Microphone)

    private func observePermissions() {
        // Re-check when returning from System Settings.
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshPermissions() }
        }
        // Poll while either permission is still missing (TCC can change without a relaunch).
        if !accessibilityGranted || !microphoneGranted {
            accessibilityTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.refreshPermissions() }
            }
        }
    }

    private func refreshPermissions() {
        let ax = AccessibilityHelper.isGranted
        if ax != accessibilityGranted { accessibilityGranted = ax }

        let mic = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        if mic != microphoneGranted { microphoneGranted = mic }

        if ax && mic { accessibilityTimer?.invalidate(); accessibilityTimer = nil }
    }

    /// Triggers the system microphone prompt if not yet determined; otherwise no-op
    /// (a denied permission can only be changed in System Settings).
    func requestMicrophone() {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
            Task { @MainActor in self?.refreshPermissions() }
        }
    }

    func openMicrophoneSettings() {
        AccessibilityHelper.openMicrophoneSettings()
    }

    func relaunch() {
        let url = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
