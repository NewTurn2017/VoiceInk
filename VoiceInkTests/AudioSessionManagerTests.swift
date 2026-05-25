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
}
