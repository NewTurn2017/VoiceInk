import AVFoundation
import Foundation

@MainActor
final class DictationController {
    private let audioManager: AudioSessionManager
    private let pipeline: SpeechPipeline
    private let textInput: TextInputService
    private let history: TranscriptHistoryManager
    private let resultModal: ResultModalController
    private let sampleRate = 16000

    var onStatusChange: ((STTStatus) -> Void)?
    var onAudioLevel: ((Float) -> Void)?
    /// Raised when recording can't start (e.g. missing key / mic denied). Title, message.
    var onError: ((String, String) -> Void)?
    /// Provides the API key presence check before recording.
    var hasAPIKey: () -> Bool = { true }

    private(set) var status: STTStatus = .idle {
        didSet { onStatusChange?(status) }
    }

    private var buffer = Data()
    private var currentMode: DictationMode = .cleanup

    init(audioManager: AudioSessionManager,
         pipeline: SpeechPipeline,
         textInput: TextInputService,
         history: TranscriptHistoryManager,
         resultModal: ResultModalController) {
        self.audioManager = audioManager
        self.pipeline = pipeline
        self.textInput = textInput
        self.history = history
        self.resultModal = resultModal
    }

    func toggle(mode: DictationMode) {
        switch status {
        case .recording: stopAndProcess()
        case .processing: return            // ignore while busy
        default: start(mode: mode)
        }
    }

    var isRecording: Bool { status == .recording }

    // MARK: - Private

    private func start(mode: DictationMode) {
        guard hasAPIKey() else {
            onError?("API Key Required",
                     "A Google AI (Gemini) API key is required.\nGo to Settings → API Key to add it.")
            return
        }
        currentMode = mode
        buffer.removeAll(keepingCapacity: true)

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            beginCapture()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                Task { @MainActor in
                    if granted { self?.beginCapture() } else { self?.status = .idle }
                }
            }
        default:
            onError?("Microphone Access Denied",
                     "Enable microphone access in System Settings → Privacy & Security → Microphone.")
        }
    }

    private func beginCapture() {
        status = .recording
        audioManager.startCapture { [weak self] data in
            guard let self else { return }
            Task { @MainActor in
                self.buffer.append(data)
            }
            self.onAudioLevel?(Self.energy(of: data))
        }
    }

    private func stopAndProcess() {
        audioManager.stopCapture()
        let captured = buffer
        // Ignore very short / empty recordings (< ~0.2s at 16k * 2 bytes/sample).
        guard captured.count > sampleRate * 2 / 5 else {
            status = .idle
            return
        }
        status = .processing
        let mode = currentMode
        let audio = RecordedAudio(pcm16: captured, sampleRate: sampleRate)

        Task { @MainActor in
            do {
                let text = try await pipeline.process(audio, mode: mode)
                let result = textInput.insert(text)
                history.add(text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                            engineType: mode.displayName)
                if result == .copiedToClipboard {
                    resultModal.show(text: text)
                }
                status = .idle
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                status = .error(message)
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                if case .error = status { status = .idle }
            }
        }
    }

    static func energy(of data: Data) -> Float {
        data.withUnsafeBytes { raw -> Float in
            guard let base = raw.baseAddress else { return 0 }
            let samples = base.assumingMemoryBound(to: Int16.self)
            let count = data.count / 2
            guard count > 0 else { return 0 }
            var sum: Float = 0
            for i in 0..<count { sum += abs(Float(samples[i]) / Float(Int16.max)) }
            return sum / Float(count)
        }
    }
}
