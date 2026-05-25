import XCTest
@testable import VoiceInk

final class GeminiPipelineTests: XCTestCase {
    override func setUp() { super.setUp(); MockURLProtocol.reset() }
    override func tearDown() { MockURLProtocol.reset(); super.tearDown() }

    private func makePipeline(key: String? = "test-key") -> GeminiPipeline {
        GeminiPipeline(
            apiKeyProvider: { key },
            model: { .flash },
            session: MockURLProtocol.makeSession()
        )
    }

    private let audio = RecordedAudio(pcm16: Data(repeating: 0, count: 3200), sampleRate: 16000)

    func testMissingKeyThrows() async {
        let pipeline = makePipeline(key: nil)
        do { _ = try await pipeline.process(audio, mode: .cleanup); XCTFail("expected throw") }
        catch { XCTAssertEqual(error as? PipelineError, .missingAPIKey) }
    }

    func testEmptyAudioThrows() async {
        let pipeline = makePipeline()
        let empty = RecordedAudio(pcm16: Data(), sampleRate: 16000)
        do { _ = try await pipeline.process(empty, mode: .cleanup); XCTFail("expected throw") }
        catch { XCTAssertEqual(error as? PipelineError, .emptyAudio) }
    }

    func testRequestShapeAndSuccess() async throws {
        MockURLProtocol.handler = { _, _ in
            let json = """
            {"candidates":[{"content":{"parts":[{"text":"  - hello\\n- world  "}]}}]}
            """
            return (200, Data(json.utf8))
        }
        let pipeline = makePipeline()
        let result = try await pipeline.process(audio, mode: .cleanup)
        XCTAssertEqual(result, "- hello\n- world")

        // Request carried the api key header and a JSON body with the system prompt + inline audio.
        XCTAssertEqual(MockURLProtocol.lastHeaders?["x-goog-api-key"], "test-key")
        let body = try XCTUnwrap(MockURLProtocol.lastBody)
        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let sys = obj["system_instruction"] as? [String: Any]
        let sysParts = sys?["parts"] as? [[String: Any]]
        XCTAssertEqual(sysParts?.first?["text"] as? String, PromptLibrary.cleanup)
        let contents = obj["contents"] as? [[String: Any]]
        let parts = contents?.first?["parts"] as? [[String: Any]]
        let inline = parts?.first?["inline_data"] as? [String: Any]
        XCTAssertEqual(inline?["mime_type"] as? String, "audio/wav")
        XCTAssertNotNil(inline?["data"] as? String)
        XCTAssertTrue((MockURLProtocol.lastURL?.absoluteString ?? "").contains("gemini-3.5-flash:generateContent"))
        let genConfig = obj["generationConfig"] as? [String: Any]
        let thinking = genConfig?["thinkingConfig"] as? [String: Any]
        XCTAssertEqual(thinking?["thinkingBudget"] as? Int, 0)
    }

    func testHTTPErrorThrows() async {
        MockURLProtocol.handler = { _, _ in (401, Data(#"{"error":"bad key"}"#.utf8)) }
        let pipeline = makePipeline()
        do { _ = try await pipeline.process(audio, mode: .cleanup); XCTFail("expected throw") }
        catch {
            guard case .http(let code, _)? = error as? PipelineError else { return XCTFail("wrong error \(error)") }
            XCTAssertEqual(code, 401)
        }
    }

    func testNoTextThrows() async {
        MockURLProtocol.handler = { _, _ in (200, Data(#"{"candidates":[]}"#.utf8)) }
        let pipeline = makePipeline()
        do { _ = try await pipeline.process(audio, mode: .cleanup); XCTFail("expected throw") }
        catch { XCTAssertEqual(error as? PipelineError, .noText) }
    }
}
