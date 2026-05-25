import Foundation

/// Wraps 16-bit PCM mono little-endian samples in a minimal WAV (RIFF) container.
enum WAVEncoder {
    static func encode(pcm16: Data, sampleRate: Int) -> Data {
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = UInt32(sampleRate) * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)
        let dataSize = UInt32(pcm16.count)
        let chunkSize = 36 + dataSize

        var d = Data(capacity: 44 + pcm16.count)
        func appendLE32(_ v: UInt32) { var x = v.littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
        func appendLE16(_ v: UInt16) { var x = v.littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }

        d.append(contentsOf: Array("RIFF".utf8))
        appendLE32(chunkSize)
        d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8))
        appendLE32(16)
        appendLE16(1)
        appendLE16(channels)
        appendLE32(UInt32(sampleRate))
        appendLE32(byteRate)
        appendLE16(blockAlign)
        appendLE16(bitsPerSample)
        d.append(contentsOf: Array("data".utf8))
        appendLE32(dataSize)
        d.append(pcm16)
        return d
    }
}
