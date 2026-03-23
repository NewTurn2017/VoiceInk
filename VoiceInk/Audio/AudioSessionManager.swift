import AVFoundation
import Foundation

final class AudioSessionManager {
    typealias AudioDataHandler = (Data) -> Void

    private var audioEngine: AVAudioEngine?
    private var converter: AVAudioConverter?
    private var onAudioData: AudioDataHandler?
    private var retryCount = 0
    private let maxRetries = 3
    private var isCapturing = false

    init() {
        setupNotifications()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func startCapture(onAudioData: @escaping AudioDataHandler) {
        self.onAudioData = onAudioData
        retryCount = 0
        startAudioEngine()
    }

    func stopCapture() {
        isCapturing = false
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        converter = nil
        onAudioData = nil
    }

    // MARK: - Private

    private func startAudioEngine() {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16000,
            channels: 1,
            interleaved: true
        ) else {
            print("Failed to create target audio format")
            return
        }

        guard let audioConverter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            print("Failed to create audio converter")
            return
        }

        self.audioEngine = engine
        self.converter = audioConverter

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer, converter: audioConverter, targetFormat: targetFormat)
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

    private func processAudioBuffer(
        _ buffer: AVAudioPCMBuffer,
        converter: AVAudioConverter,
        targetFormat: AVAudioFormat
    ) {
        guard isCapturing else { return }

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
        onAudioData?(data)
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

        // Stop current engine and attempt reconnect
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        converter = nil

        attemptReconnect()
    }

    private func attemptReconnect() {
        guard retryCount < maxRetries, onAudioData != nil else {
            if retryCount >= maxRetries {
                print("Max audio reconnect attempts reached (\(maxRetries))")
            }
            return
        }

        retryCount += 1
        let delay = pow(2.0, Double(retryCount - 1)) // 1s, 2s, 4s
        print("Attempting audio reconnect (\(retryCount)/\(maxRetries)) in \(delay)s...")

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.startAudioEngine()
        }
    }
}
