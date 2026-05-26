import AVFoundation
import Foundation

final class AudioSessionManager {
    typealias AudioLevelHandler = (Float) -> Void

    private var audioEngine: AVAudioEngine?
    private var int16Converter: AVAudioConverter?
    private var onLevel: AudioLevelHandler?
    private var retryCount = 0
    private let maxRetries = 3
    private var isCapturing = false

    /// Accumulates the full 16 kHz mono Int16 recording. Guarded by `accumulatorLock`
    /// so the audio tap thread and the stop call never race. Persists across an
    /// AVAudioEngineConfigurationChange reconnect; only `startCapture` clears it.
    private var accumulator = Data()
    private let accumulatorLock = NSLock()

    init() {
        setupNotifications()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func startCapture(onLevel: @escaping AudioLevelHandler) {
        self.onLevel = onLevel
        accumulatorLock.lock()
        accumulator.removeAll(keepingCapacity: true)
        accumulatorLock.unlock()
        retryCount = 0
        startAudioEngine()
    }

    /// Stops capture and returns the complete recorded buffer synchronously.
    @discardableResult
    func stopCapture() -> Data {
        isCapturing = false
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        int16Converter = nil
        onLevel = nil

        accumulatorLock.lock()
        let data = accumulator
        accumulator.removeAll()
        accumulatorLock.unlock()
        return data
    }

    // MARK: - Private

    private func startAudioEngine() {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Int16 converter for the Gemini pipeline (16 kHz mono).
        if let fmt = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true) {
            self.int16Converter = AVAudioConverter(from: inputFormat, to: fmt)
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

        guard let converter = int16Converter,
              let data = convertToInt16Data(buffer, converter: converter) else { return }

        accumulatorLock.lock()
        accumulator.append(data)
        accumulatorLock.unlock()

        onLevel?(Self.energy(ofInt16: data))
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

    /// Mean absolute amplitude (0...1) of little-endian Int16 samples in `data`.
    static func energy(ofInt16 data: Data) -> Float {
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

    /// Peak absolute amplitude (0...1) over the buffer. Used to tell speech from
    /// silence: real speech peaks well above the noise floor, so a low peak means
    /// the recording was effectively silent.
    static func peakAmplitude(ofInt16 data: Data) -> Float {
        data.withUnsafeBytes { raw -> Float in
            guard let base = raw.baseAddress else { return 0 }
            let samples = base.assumingMemoryBound(to: Int16.self)
            let count = data.count / 2
            guard count > 0 else { return 0 }
            var peak: Int32 = 0
            for i in 0..<count { peak = max(peak, abs(Int32(samples[i]))) }
            return Float(peak) / Float(Int16.max)
        }
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

        attemptReconnect()
    }

    private func attemptReconnect() {
        guard retryCount < maxRetries, onLevel != nil else {
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
