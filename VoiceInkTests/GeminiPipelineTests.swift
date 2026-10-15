import XCTest
@testable import VoiceInk

final class GeminiPipelineTests: XCTestCase {
    override func setUp() { super.setUp(); MockURLProtocol.reset() }
    override func tearDown() { MockURLProtocol.reset(); super.tearDown() }

    private func makePipeline(key: String? = "test-key", model: GeminiModel = .flash) -> GeminiPipeline {
        GeminiPipeline(
            apiKeyProvider: { key },
            model: { model },
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
        XCTAssertEqual(result.text, "- hello\n- world")

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
        XCTAssertTrue((MockURLProtocol.lastURL?.absoluteString ?? "").contains("gemini-3.8-flash:generateContent"))
        let genConfig = obj["generationConfig"] as? [String: Any]
        let thinking = genConfig?["thinkingConfig"] as? [String: Any]
        XCTAssertEqual(thinking?["thinkingLevel"] as? String, "low")
        XCTAssertNil(thinking?["thinkingBudget"])
    }

    func testEconomyModelTurnsThinkingOff() async throws {
        MockURLProtocol.handler = { _, _ in
            (200, Data(#"{"candidates":[{"content":{"parts":[{"text":"ok"}]}}]}"#.utf8))
        }
        _ = try await makePipeline(model: .flashEconomy).process(audio, mode: .cleanup)
        XCTAssertTrue((MockURLProtocol.lastURL?.absoluteString ?? "").contains("gemini-2.5-flash:generateContent"))
        let body = try XCTUnwrap(MockURLProtocol.lastBody)
        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let thinking = (obj["generationConfig"] as? [String: Any])?["thinkingConfig"] as? [String: Any]
        XCTAssertEqual(thinking?["thinkingBudget"] as? Int, 0)
        XCTAssertNil(thinking?["thinkingLevel"])
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

    func testMultiPartTextIsConcatenated() async throws {
        MockURLProtocol.handler = { _, _ in
            let json = #"{"candidates":[{"content":{"parts":[{"text":"a"},{"text":"b"}]}}]}"#
            return (200, Data(json.utf8))
        }
        let pipeline = makePipeline()
        let result = try await pipeline.process(audio, mode: .cleanup)
        XCTAssertEqual(result.text, "ab")
    }

    func testParsesUsageMetadata() async throws {
        MockURLProtocol.handler = { _, _ in
            let json = """
            {"candidates":[{"content":{"parts":[{"text":"hi"}]}}],
             "usageMetadata":{"promptTokenCount":1100,"candidatesTokenCount":40,
               "promptTokensDetails":[{"modality":"AUDIO","tokenCount":1000},{"modality":"TEXT","tokenCount":100}]}}
            """
            return (200, Data(json.utf8))
        }
        let pipeline = makePipeline()
        let result = try await pipeline.process(audio, mode: .cleanup)
        XCTAssertEqual(result.usage?.audioInputTokens, 1000)
        XCTAssertEqual(result.usage?.textInputTokens, 100)
        XCTAssertEqual(result.usage?.outputTokens, 40)
    }

    func testThinkingTokensCountAsOutput() async throws {
        MockURLProtocol.handler = { _, _ in
            let json = """
            {"candidates":[{"content":{"parts":[{"text":"hi"}]}}],
             "usageMetadata":{"promptTokenCount":500,"candidatesTokenCount":40,"thoughtsTokenCount":25}}
            """
            return (200, Data(json.utf8))
        }
        let result = try await makePipeline().process(audio, mode: .cleanup)
        XCTAssertEqual(result.usage?.outputTokens, 65)
    }

    func testFlashLaunchDiscountEndsIn2027() throws {
        let iso = ISO8601DateFormatter()
        let lastDiscountedDay = try XCTUnwrap(iso.date(from: "2026-12-31T12:00:00Z"))
        let firstListPriceDay = try XCTUnwrap(iso.date(from: "2027-01-01T12:00:00Z"))
        XCTAssertEqual(GeminiModel.launchDiscount(on: lastDiscountedDay), 0.5)
        XCTAssertEqual(GeminiModel.launchDiscount(on: firstListPriceDay), 1.0)
    }
}
