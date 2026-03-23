import AVFoundation
import Foundation

final class AudioSessionManager {
    typealias AudioDataHandler = (Data) -> Void
    typealias AudioFloatHandler = ([Float]) -> Void

    private var audioEngine: AVAudioEngine?
    private var int16Converter: AVAudioConverter?
    private var float32Converter: AVAudioConverter?
    private var onAudioData: AudioDataHandler?
    private var onAudioFloat: AudioFloatHandler?
    private var retryCount = 0
    private let maxRetries = 3
    private var isCapturing = false

    init() {
        setupNotifications()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func startCapture(
        onAudioData: AudioDataHandler? = nil,
        onAudioFloat: AudioFloatHandler? = nil
    ) {
        self.onAudioData = onAudioData
        self.onAudioFloat = onAudioFloat
        retryCount = 0
        startAudioEngine()
    }

    func stopCapture() {
        isCapturing = false
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        int16Converter = nil
        float32Converter = nil
        onAudioData = nil
        onAudioFloat = nil
    }

    // MARK: - Private

    private func startAudioEngine() {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Int16 converter for CloudSTTEngine
        if onAudioData != nil {
            if let fmt = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true) {
                self.int16Converter = AVAudioConverter(from: inputFormat, to: fmt)
            }
        }

        // Float32 converter for LocalSTTEngine
        if onAudioFloat != nil {
            if let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false) {
                self.float32Converter = AVAudioConverter(from: inputFormat, to: fmt)
            }
        }

        self.audioEngine = engine

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer)
        }

        do {
            try engine.start()
            isCapturing = true
            retryCount = 0
            print("Audio engine started")
        } catch {
            print("Failed to start audio engine: \(error)")
            attemptReconnect()
        }
    }

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard isCapturing else { return }

        // Int16 path (CloudSTTEngine)
        if let converter = int16Converter, let handler = onAudioData {
            if let data = convertToInt16Data(buffer, converter: converter) {
                handler(data)
            }
        }

        // Float32 path (LocalSTTEngine)
        if let converter = float32Converter, let handler = onAudioFloat {
            if let floats = convertToFloat32(buffer, converter: converter) {
                handler(floats)
            }
        }
    }

    private func convertToInt16Data(_ buffer: AVAudioPCMBuffer, converter: AVAudioConverter) -> Data? {
        let targetFormat = converter.outputFormat
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let frameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)

        guard frameCount > 0,
              let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCount) else {
            return nil
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
        if status == .error { return nil }

        guard convertedBuffer.frameLength > 0,
              let channelData = convertedBuffer.int16ChannelData else { return nil }

        return Data(bytes: channelData[0], count: Int(convertedBuffer.frameLength) * 2)
    }

    private func convertToFloat32(_ buffer: AVAudioPCMBuffer, converter: AVAudioConverter) -> [Float]? {
        let targetFormat = converter.outputFormat
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let frameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)

        guard frameCount > 0,
              let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCount) else {
            return nil
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
        if status == .error { return nil }

        guard convertedBuffer.frameLength > 0,
              let channelData = convertedBuffer.floatChannelData else { return nil }

        let count = Int(convertedBuffer.frameLength)
        return Array(UnsafeBufferPointer(start: channelData[0], count: count))
    }

    // MARK: - Reconnection

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleConfigurationChange),
            name: .AVAudioEngineConfigurationChange,
            object: nil
        )
    }

    @objc private func handleConfigurationChange(_ notification: Notification) {
        print("Audio configuration changed")
        guard isCapturing else { return }

        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        int16Converter = nil
        float32Converter = nil

        attemptReconnect()
    }

    private func attemptReconnect() {
        guard retryCount < maxRetries, (onAudioData != nil || onAudioFloat != nil) else {
            if retryCount >= maxRetries {
                print("Max audio reconnect attempts reached (\(maxRetries))")
            }
            return
        }

        retryCount += 1
        let delay = pow(2.0, Double(retryCount - 1))
        print("Attempting audio reconnect (\(retryCount)/\(maxRetries)) in \(delay)s...")

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.startAudioEngine()
        }
    }
}
