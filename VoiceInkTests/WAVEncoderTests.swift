import XCTest
@testable import VoiceInk

final class WAVEncoderTests: XCTestCase {
    func testHeaderAndLength() {
        // 4 samples of Int16 = 8 bytes of PCM
        let pcm = Data([0x01, 0x00, 0x02, 0x00, 0x03, 0x00, 0x04, 0x00])
        let wav = WAVEncoder.encode(pcm16: pcm, sampleRate: 16000)

        // 44-byte header + data
        XCTAssertEqual(wav.count, 44 + pcm.count)

        func ascii(_ range: Range<Int>) -> String {
            String(bytes: wav[range], encoding: .ascii)!
        }
        XCTAssertEqual(ascii(0..<4), "RIFF")
        XCTAssertEqual(ascii(8..<12), "WAVE")
        XCTAssertEqual(ascii(12..<16), "fmt ")
        XCTAssertEqual(ascii(36..<40), "data")

        func le32(_ offset: Int) -> UInt32 {
            UInt32(wav[offset]) | UInt32(wav[offset+1]) << 8 | UInt32(wav[offset+2]) << 16 | UInt32(wav[offset+3]) << 24
        }
        func le16(_ offset: Int) -> UInt16 {
            UInt16(wav[offset]) | UInt16(wav[offset+1]) << 8
        }
        XCTAssertEqual(le32(4), 36 + UInt32(pcm.count))   // RIFF chunk size
        XCTAssertEqual(le32(16), 16)                       // PCM fmt size
        XCTAssertEqual(le16(20), 1)                        // PCM format tag
        XCTAssertEqual(le16(22), 1)                        // mono
        XCTAssertEqual(le32(24), 16000)                    // sample rate
        XCTAssertEqual(le32(28), 16000 * 2)                // byte rate
        XCTAssertEqual(le16(32), 2)                        // block align
        XCTAssertEqual(le16(34), 16)                       // bits per sample
        XCTAssertEqual(le32(40), UInt32(pcm.count))        // data size
        XCTAssertEqual(Data(wav[44...]), pcm)              // payload preserved
    }
}
