import Foundation
import AVFoundation

enum STTStatus {
    case idle
    case connecting
    case recording
    case error
}

class STTManager: NSObject, URLSessionWebSocketDelegate {
    var onTranscript: ((String) -> Void)?
    var onStatusChange: ((STTStatus) -> Void)?
    
    private var audioEngine: AVAudioEngine?
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var isConnected = false
    private let apiKey: String
    
    override init() {
        self.apiKey = ProcessInfo.processInfo.environment["ELEVENLABS_API_KEY"]
            ?? "YOUR_API_KEY_HERE"
        super.init()
    }
    
    func startRecording() {
        print("📍 startRecording called")
        onStatusChange?(.connecting)
        
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            print("✅ Microphone already authorized")
            connectWebSocket()
        case .notDetermined:
            print("🔄 Requesting microphone permission...")
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                if granted {
                    print("✅ Microphone access granted")
                    DispatchQueue.main.async {
                        self?.connectWebSocket()
                    }
                } else {
                    print("❌ Microphone access denied")
                    DispatchQueue.main.async {
                        self?.onStatusChange?(.idle)
                    }
                }
            }
        default:
            print("❌ Microphone access denied")
            onStatusChange?(.idle)
        }
    }
    
    func stopRecording() {
        print("📍 stopRecording called")
        
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
        
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        
        // Give time for final commit response
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.webSocketTask?.cancel(with: .normalClosure, reason: nil)
            self?.webSocketTask = nil
            self?.urlSession?.invalidateAndCancel()
            self?.urlSession = nil
        }
        
        onStatusChange?(.idle)
    }
    
    private func connectWebSocket() {
        print("📍 connectWebSocket called")
        
        // ElevenLabs Realtime STT WebSocket endpoint
        let urlString = "wss://api.elevenlabs.io/v1/speech-to-text/realtime?model_id=scribe_v2_realtime&language_code=ko&commit_strategy=vad&vad_silence_threshold_secs=1.0"
        
        guard let wsUrl = URL(string: urlString) else {
            print("❌ Invalid URL")
            onStatusChange?(.idle)
            return
        }
        
        print("🔗 Connecting to: \(wsUrl)")
        
        var request = URLRequest(url: wsUrl)
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.timeoutInterval = 30
        
        let config = URLSessionConfiguration.default
        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: .main)
        webSocketTask = urlSession?.webSocketTask(with: request)
        webSocketTask?.resume()
        
        // Start receiving messages
        receiveMessage()
    }
    
    // MARK: - URLSessionWebSocketDelegate
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        print("✅ WebSocket connected!")
        isConnected = true
        
        // Start audio capture after connection is established
        startAudioCapture()
        
        DispatchQueue.main.async {
            self.onStatusChange?(.recording)
        }
    }
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        print("🔌 WebSocket closed: \(closeCode.rawValue)")
        if let reason = reason, let reasonStr = String(data: reason, encoding: .utf8) {
            print("   Reason: \(reasonStr)")
        }
        isConnected = false
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            print("❌ WebSocket error: \(error.localizedDescription)")
            isConnected = false
            DispatchQueue.main.async {
                self.onStatusChange?(.idle)
            }
        }
    }
    
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
                // Continue receiving if still connected
                if self.isConnected {
                    self.receiveMessage()
                }
                
            case .failure(let error):
                print("⚠️ Receive error: \(error.localizedDescription)")
                // Don't stop on receive error, connection might still be alive
                if self.isConnected {
                    self.receiveMessage()
                }
            }
        }
    }
    
    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("📩 Raw message: \(text)")
            return
        }
        
        let messageType = json["message_type"] as? String ?? json["type"] as? String ?? ""
        
        switch messageType {
        case "session_started":
            print("✅ Session started: \(json)")
            
        case "partial_transcript":
            if let transcript = json["text"] as? String, !transcript.isEmpty {
                print("📝 Partial: \(transcript)")
            }
            
        case "committed_transcript":
            if let transcript = json["text"] as? String, !transcript.isEmpty {
                print("✅ Committed: \(transcript)")
                DispatchQueue.main.async {
                    self.onTranscript?(transcript + " ")
                }
            }
            
        case "committed_transcript_with_timestamps":
            // Skip this - we already handle committed_transcript
            if let transcript = json["text"] as? String {
                print("📊 Timestamps for: \(transcript)")
            }
            
        case "auth_error", "quota_exceeded", "transcriber_error", "input_error", "error":
            print("❌ Error [\(messageType)]: \(json["message"] ?? json["error"] ?? json)")
            
        default:
            print("📩 Message [\(messageType)]: \(json)")
        }
    }
    
    private func startAudioCapture() {
        print("📍 startAudioCapture called")
        
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else {
            print("❌ Failed to create audio engine")
            return
        }
        
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        print("🎤 Input format: \(inputFormat)")
        
        guard let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true) else {
            print("❌ Failed to create target format")
            return
        }
        
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            print("❌ Failed to create audio converter")
            return
        }
        
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer, converter: converter, targetFormat: targetFormat)
        }
        
        do {
            try audioEngine.start()
            print("✅ Audio engine started")
        } catch {
            print("❌ Failed to start audio engine: \(error)")
        }
    }
    
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, converter: AVAudioConverter, targetFormat: AVAudioFormat) {
        guard isConnected else { return }
        
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let frameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
        
        guard frameCount > 0,
              let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCount) else {
            return
        }
        
        var error: NSError?
        var hasData = true
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if hasData {
                hasData = false
                outStatus.pointee = .haveData
                return buffer
            }
            outStatus.pointee = .noDataNow
            return nil
        }
        
        let status = converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)
        
        if status == .error { return }
        
        guard convertedBuffer.frameLength > 0,
              let channelData = convertedBuffer.int16ChannelData else { return }
        
        let data = Data(bytes: channelData[0], count: Int(convertedBuffer.frameLength) * 2)
        let base64Audio = data.base64EncodedString()
        
        // Send audio chunk using ElevenLabs format
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
                    print("⚠️ Send error: \(error.localizedDescription)")
                }
            }
        }
    }
}
