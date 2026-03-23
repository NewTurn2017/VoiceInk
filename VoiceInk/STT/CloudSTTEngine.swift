import Foundation

final class CloudSTTEngine: NSObject, STTEngine, URLSessionWebSocketDelegate {
    var onTranscript: ((String) -> Void)?
    var onStatusChange: ((STTStatus) -> Void)?
    var onAudioLevel: ((Float) -> Void)?
    private(set) var currentStatus: STTStatus = .idle

    private let keychainManager: KeychainManager
    private let audioManager: AudioSessionManager
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var isConnected = false

    init(keychainManager: KeychainManager, audioManager: AudioSessionManager) {
        self.keychainManager = keychainManager
        self.audioManager = audioManager
        super.init()
    }

    func start() {
        guard let apiKey = keychainManager.getAPIKey(for: .elevenLabs) else {
            updateStatus(.error("API key not configured"))
            return
        }

        updateStatus(.connecting)

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            connectWebSocket(apiKey: apiKey)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.connectWebSocket(apiKey: apiKey)
                    } else {
                        self?.updateStatus(.idle)
                    }
                }
            }
        default:
            updateStatus(.error("Microphone access denied"))
        }
    }

    func stop() {
        // Send final commit before closing
        if isConnected {
            let commitMessage: [String: Any] = [
                "message_type": "input_audio_chunk",
                "audio_base_64": "",
                "commit": true,
                "sample_rate": 16000
            ]
            if let jsonData = try? JSONSerialization.data(withJSONObject: commitMessage),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                webSocketTask?.send(.string(jsonString)) { _ in }
            }
        }

        isConnected = false
        audioManager.stopCapture()

        // Give time for final commit response
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.webSocketTask?.cancel(with: .normalClosure, reason: nil)
            self?.webSocketTask = nil
            self?.urlSession?.invalidateAndCancel()
            self?.urlSession = nil
        }

        updateStatus(.idle)
    }

    // MARK: - WebSocket

    private func connectWebSocket(apiKey: String) {
        let urlString = "wss://api.elevenlabs.io/v1/speech-to-text/realtime?model_id=scribe_v2_realtime&language_code=ko&commit_strategy=vad&vad_silence_threshold_secs=1.0"

        guard let wsUrl = URL(string: urlString) else {
            updateStatus(.error("Invalid WebSocket URL"))
            return
        }

        var request = URLRequest(url: wsUrl)
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.timeoutInterval = 30

        let config = URLSessionConfiguration.default
        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: .main)
        webSocketTask = urlSession?.webSocketTask(with: request)
        webSocketTask?.resume()

        receiveMessage()
    }

    // MARK: - URLSessionWebSocketDelegate

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        isConnected = true
        startAudioCapture()
        updateStatus(.recording)
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        isConnected = false
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            print("WebSocket error: \(error.localizedDescription)")
            isConnected = false
            updateStatus(.idle)
        }
    }

    // MARK: - Audio Capture

    private func startAudioCapture() {
        audioManager.startCapture(onAudioData: { [weak self] audioData in
            self?.sendAudioData(audioData)
        })
    }

    private func sendAudioData(_ data: Data) {
        guard isConnected else { return }

        // Compute audio energy from Int16 samples
        data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            let int16Buffer = baseAddress.assumingMemoryBound(to: Int16.self)
            let sampleCount = data.count / 2
            guard sampleCount > 0 else { return }
            var sum: Float = 0
            for i in 0..<sampleCount {
                sum += abs(Float(int16Buffer[i]) / Float(Int16.max))
            }
            let energy = sum / Float(sampleCount)
            DispatchQueue.main.async { [weak self] in
                self?.onAudioLevel?(energy)
            }
        }

        let base64Audio = data.base64EncodedString()
        let message: [String: Any] = [
            "message_type": "input_audio_chunk",
            "audio_base_64": base64Audio,
            "commit": false,
            "sample_rate": 16000
        ]

        if let jsonData = try? JSONSerialization.data(withJSONObject: message),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            webSocketTask?.send(.string(jsonString)) { error in
                if let error = error {
                    print("Send error: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Message Handling

    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleMessage(text)
                    }
                @unknown default:
                    break
                }
                if self.isConnected {
                    self.receiveMessage()
                }

            case .failure(let error):
                print("Receive error: \(error.localizedDescription)")
                if self.isConnected {
                    self.receiveMessage()
                }
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        let messageType = json["message_type"] as? String ?? json["type"] as? String ?? ""

        switch messageType {
        case "session_started":
            print("STT session started")

        case "partial_transcript":
            // Partial transcripts can be used for real-time preview in the future
            break

        case "committed_transcript":
            if let transcript = json["text"] as? String, !transcript.isEmpty {
                DispatchQueue.main.async {
                    self.onTranscript?(transcript + " ")
                }
            }

        case "committed_transcript_with_timestamps":
            break // Already handled via committed_transcript

        case "auth_error", "quota_exceeded", "transcriber_error", "input_error", "error":
            let errorMsg = json["message"] as? String ?? json["error"] as? String ?? messageType
            print("STT error [\(messageType)]: \(errorMsg)")

        default:
            break
        }
    }

    // MARK: - Helpers

    private func updateStatus(_ status: STTStatus) {
        currentStatus = status
        DispatchQueue.main.async {
            self.onStatusChange?(status)
        }
    }
}

import AVFoundation
