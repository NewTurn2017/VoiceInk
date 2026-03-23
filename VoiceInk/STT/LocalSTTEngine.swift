import Foundation
import Qwen3ASR

final class LocalSTTEngine: STTEngine {
    var onTranscript: ((String) -> Void)?
    var onStatusChange: ((STTStatus) -> Void)?
    var onModelProgress: ((Double, String) -> Void)?
    private(set) var currentStatus: STTStatus = .idle

    private var model: Qwen3ASRModel?
    private let audioManager: AudioSessionManager
    private var audioBuffer: [Float] = []
    private let modelId: String
    private var isListening = false
    private let language = "korean"

    // Accumulate ~2 seconds of audio before transcribing (16000 Hz * 2 = 32000 samples)
    private let silenceThresholdSamples = 32000
    // Maximum buffer before forced transcription (~10 seconds)
    private let maxBufferSamples = 160000

    private var silenceCounter = 0
    private let silenceThreshold: Float = 0.01
    private let silenceChunksNeeded = 8 // ~8 consecutive quiet chunks = ~2s of silence

    init(audioManager: AudioSessionManager, modelId: String = STTModelSize.small.rawValue) {
        self.audioManager = audioManager
        self.modelId = modelId
    }

    func start() {
        updateStatus(.connecting)

        Task {
            do {
                if model == nil || !model!.isLoaded {
                    let loadedModel = try await Qwen3ASRModel.fromPretrained(
                        modelId: modelId
                    ) { [weak self] progress, status in
                        DispatchQueue.main.async {
                            self?.onModelProgress?(progress, status)
                        }
                    }
                    self.model = loadedModel
                }

                await MainActor.run {
                    self.startListening()
                }
            } catch {
                await MainActor.run {
                    self.updateStatus(.error("Model load failed: \(error.localizedDescription)"))
                }
            }
        }
    }

    func stop() {
        isListening = false
        audioManager.stopCapture()

        // Transcribe any remaining audio
        if !audioBuffer.isEmpty {
            transcribeBuffer()
        }

        updateStatus(.idle)
    }

    // MARK: - Private

    private func startListening() {
        audioBuffer = []
        silenceCounter = 0
        isListening = true
        updateStatus(.recording)

        audioManager.startCapture(onAudioFloat: { [weak self] samples in
            self?.handleAudioSamples(samples)
        })
    }

    private func handleAudioSamples(_ samples: [Float]) {
        guard isListening else { return }

        audioBuffer.append(contentsOf: samples)

        // Simple energy-based silence detection
        let energy = samples.reduce(0) { $0 + abs($1) } / Float(samples.count)

        if energy < silenceThreshold {
            silenceCounter += 1
        } else {
            silenceCounter = 0
        }

        // Transcribe when: silence detected after speech, or buffer is too large
        let hasSpeech = audioBuffer.count > silenceThresholdSamples
        let silenceDetected = silenceCounter >= silenceChunksNeeded
        let bufferFull = audioBuffer.count >= maxBufferSamples

        if hasSpeech && (silenceDetected || bufferFull) {
            transcribeBuffer()
        }
    }

    private func transcribeBuffer() {
        guard let model = model, !audioBuffer.isEmpty else { return }

        let samples = audioBuffer
        audioBuffer = []
        silenceCounter = 0

        // Run transcription off main thread
        Task.detached { [weak self] in
            guard let self = self else { return }

            let text = model.transcribe(
                audio: samples,
                sampleRate: 16000,
                language: self.language,
                maxTokens: 448
            )

            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                await MainActor.run {
                    self.onTranscript?(trimmed + " ")
                }
            }
        }
    }

    private func updateStatus(_ status: STTStatus) {
        currentStatus = status
        DispatchQueue.main.async {
            self.onStatusChange?(status)
        }
    }
}
