import XCTest
@testable import VoiceInk

final class AudioSessionManagerTests: XCTestCase {
    /// Builds little-endian Int16 PCM Data from sample values.
    private func pcm16(_ samples: [Int16]) -> Data {
        var d = Data(capacity: samples.count * 2)
        for s in samples {
            var le = s.littleEndian
            withUnsafeBytes(of: &le) { d.append(contentsOf: $0) }
        }
        return d
    }

    func testEnergyOfSilenceIsZero() {
        let data = pcm16(Array(repeating: 0, count: 100))
        XCTAssertEqual(AudioSessionManager.energy(ofInt16: data), 0.0)
    }

    func testEnergyOfFullScaleIsApproximatelyOne() {
        let data = pcm16(Array(repeating: Int16.max, count: 100))
        XCTAssertEqual(AudioSessionManager.energy(ofInt16: data), 1.0, accuracy: 0.01)
    }

    func testEnergyOfEmptyIsZero() {
        XCTAssertEqual(AudioSessionManager.energy(ofInt16: Data()), 0.0)
    }

    func testPeakAmplitudeOfSilenceIsZero() {
        let data = pcm16(Array(repeating: 0, count: 100))
        XCTAssertEqual(AudioSessionManager.peakAmplitude(ofInt16: data), 0.0)
    }

    func testPeakAmplitudeUsesLoudestSample() {
        // Mostly quiet with one loud sample → peak reflects the loud one, not the mean.
        var samples = Array<Int16>(repeating: 10, count: 100)
        samples[50] = Int16.max
        XCTAssertEqual(AudioSessionManager.peakAmplitude(ofInt16: pcm16(samples)), 1.0, accuracy: 0.01)
    }

    func testPeakAmplitudeHandlesInt16Min() {
        // abs(Int16.min) must not overflow.
        let data = pcm16([Int16.min])
        XCTAssertEqual(AudioSessionManager.peakAmplitude(ofInt16: data), 1.0, accuracy: 0.01)
    }
}
