# Gemini Batch Dictation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace VoiceInk's local Qwen3-ASR + ElevenLabs streaming STT with a batch audio-native Gemini pipeline that transcribes, cleans up, and optionally translates a full recording in one API call, inserting the result at the cursor or falling back to a clipboard modal.

**Architecture:** Toggle recording accumulates 16 kHz mono Int16 PCM in memory. On stop, the buffer is wrapped in a WAV container and sent to Gemini (`generateContent`) with a mode-specific system prompt. The returned cleaned text is pasted at the focused editable element, or shown in a crystal-glass result modal if no editable field is focused. All STT/LLM access goes through a swappable `SpeechPipeline` protocol so a 2-step pipeline can be added later without touching callers.

**Tech Stack:** Swift 5.9, SwiftUI, AppKit (NSPanel/NSPasteboard/CGEvent), Carbon hotkeys, AVFoundation capture, Gemini REST API, XcodeGen, XCTest.

**Spec:** `docs/superpowers/specs/2026-05-26-voiceink-gemini-dictation-design.md`

---

## Build & Test Commands (reference)

Run from repo root `/Users/genie/dev/side/VoiceInk`.

- Regenerate Xcode project after editing `project.yml`:
  `xcodegen generate`
- Build: `xcodebuild build -project VoiceInk.xcodeproj -scheme VoiceInk -destination 'platform=macOS' -quiet`
- Test: `xcodebuild test -project VoiceInk.xcodeproj -scheme VoiceInk -destination 'platform=macOS' -quiet`
- If code signing blocks logic tests in this environment, append: `CODE_SIGNING_ALLOWED=NO`

`xcodegen generate` rewrites `VoiceInk.xcodeproj/project.pbxproj` (tracked in git) — commit it together with `project.yml` changes.

> **Model/endpoint — verified 2026-05-26.** The benchmark (`/tmp/voiceink-bench/bench_gemini.py`) confirmed against the live API with the user's key: model ids `gemini-3.5-flash` (default) and `gemini-2.5-flash` (economy) both accept audio via `POST v1beta/models/{model}:generateContent` with the `x-goog-api-key` header and inline `audio/wav` data, and honor `generationConfig.thinkingConfig.thinkingBudget = 0`. End-to-end latency for a 13.6s / 103-char Korean clip was ~2.0s (3.5-flash) and ~2.7s (2.5-flash) with thinking off. These constants are final unless the API changes.

---

## File Structure

**New files:**
- `VoiceInk/Pipeline/SpeechPipeline.swift` — `RecordedAudio`, `PipelineError`, `SpeechPipeline` protocol
- `VoiceInk/Pipeline/WAVEncoder.swift` — Int16 PCM → WAV(RIFF) bytes
- `VoiceInk/Pipeline/GeminiPipeline.swift` — `GeminiModel` enum + Gemini one-call implementation
- `VoiceInk/Dictation/DictationMode.swift` — mode enum (cleanup / translateToEnglish)
- `VoiceInk/Dictation/PromptLibrary.swift` — system prompts per mode
- `VoiceInk/Dictation/DictationController.swift` — record buffer → pipeline → insert orchestration
- `VoiceInk/Views/ResultModal.swift` — crystal-glass result panel + `ResultModalController`
- `VoiceInkTests/WAVEncoderTests.swift`
- `VoiceInkTests/PromptLibraryTests.swift`
- `VoiceInkTests/GeminiPipelineTests.swift`
- `VoiceInkTests/TextInputServiceTests.swift`
- `VoiceInkTests/MockURLProtocol.swift` — test helper

**Modified files:**
- `project.yml` — drop `Qwen3Speech` package+dependency; add `VoiceInkTests` target and `VoiceInk` scheme with test action
- `VoiceInk/STT/STTStatus.swift` — replace `.connecting` with `.processing`
- `VoiceInk/Security/KeychainManager.swift` — `APIKeyService.gemini`, remove `.elevenLabs`
- `VoiceInk/Hotkey/HotkeyManager.swift` — multi-binding, `onHotkey: (DictationMode)->Void`
- `VoiceInk/TextInput/TextInputService.swift` — `insert(_:) -> InsertResult`, AX focus detection
- `VoiceInk/Audio/AudioSessionManager.swift` — remove unused Float32 path
- `VoiceInk/AppState.swift` — use `DictationController`, drop engine/model, test-env guard
- `VoiceInk/Views/RecordingOverlay.swift` — crystal-glass capsule with waveform / Thinking states
- `VoiceInk/Views/MenuBarView.swift` — new statuses, drop engine/model lines, modes hint
- `VoiceInk/Views/SettingsView.swift` — drop Engine/local-model UI; Gemini model picker + Gemini API key

**Deleted files:**
- `VoiceInk/STT/STTEngine.swift`
- `VoiceInk/STT/LocalSTTEngine.swift`
- `VoiceInk/STT/CloudSTTEngine.swift`
- `VoiceInk/STT/ModelConfiguration.swift`

---

## Phase 0 — Project cleanup & test target

### Task 0.1: Remove Qwen3Speech, delete old STT engine files

**Files:**
- Modify: `project.yml`
- Delete: `VoiceInk/STT/STTEngine.swift`, `VoiceInk/STT/LocalSTTEngine.swift`, `VoiceInk/STT/CloudSTTEngine.swift`, `VoiceInk/STT/ModelConfiguration.swift`

- [x] **Step 1: Delete the four old STT files**

```bash
cd /Users/genie/dev/side/VoiceInk
git rm VoiceInk/STT/STTEngine.swift VoiceInk/STT/LocalSTTEngine.swift VoiceInk/STT/CloudSTTEngine.swift VoiceInk/STT/ModelConfiguration.swift
```

- [x] **Step 2: Edit `project.yml` — remove Qwen3Speech package and dependency, add test target + scheme**

Replace the `packages:` block so only Sparkle remains:

```yaml
packages:
  Sparkle:
    url: https://github.com/sparkle-project/Sparkle
    exactVersion: "2.9.0"
```

In `targets.VoiceInk.dependencies`, remove the Qwen3Speech entry so it reads:

```yaml
    dependencies:
      - package: Sparkle
        product: Sparkle
```

Add a test target after the `VoiceInk` target (sibling under `targets:`):

```yaml
  VoiceInkTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - path: VoiceInkTests
    dependencies:
      - target: VoiceInk
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.voiceink.tests
        GENERATE_INFOPLIST_FILE: YES
```

Add a top-level `schemes:` block (sibling of `targets:`) so `xcodebuild test -scheme VoiceInk` runs the tests:

```yaml
schemes:
  VoiceInk:
    build:
      targets:
        VoiceInk: all
    test:
      targets:
        - VoiceInkTests
    run: {}
```

- [x] **Step 3: Create the test sources directory with a placeholder so XcodeGen accepts it**

```bash
mkdir -p VoiceInkTests
```

Create `VoiceInkTests/SmokeTests.swift`:

```swift
import XCTest
@testable import VoiceInk

final class SmokeTests: XCTestCase {
    func testTrue() {
        XCTAssertTrue(true)
    }
}
```

- [x] **Step 4: Regenerate and build**

Run: `xcodegen generate`
Expected: "Created project at VoiceInk.xcodeproj". The app will no longer compile yet because `AppState.swift` and `SettingsView.swift` still reference deleted types — that is fixed in Phase 1. For now just confirm generation succeeds and the package graph drops MLX/hummingbird/nio:

Run: `xcodebuild -list -project VoiceInk.xcodeproj 2>&1 | tail -20`
Expected: "Qwen3Speech" no longer in the resolved packages list; schemes include `VoiceInk`.

- [x] **Step 5: Commit**

```bash
git add -A
git commit -m "chore: drop Qwen3Speech + old STT engines, add test target"
```

---

## Phase 1 — Status enum & Keychain

### Task 1.1: Update STTStatus

**Files:**
- Modify: `VoiceInk/STT/STTStatus.swift`

- [x] **Step 1: Replace file contents**

```swift
import Foundation

enum STTStatus: Equatable {
    case idle
    case recording
    case processing
    case error(String?)
}
```

- [x] **Step 2: Commit** (build still red until Phase 9 — that's expected)

```bash
git add VoiceInk/STT/STTStatus.swift
git commit -m "refactor: STTStatus add .processing, drop .connecting"
```

### Task 1.2: Switch Keychain to Gemini

**Files:**
- Modify: `VoiceInk/Security/KeychainManager.swift`

- [x] **Step 1: Replace the `APIKeyService` enum**

```swift
enum APIKeyService: String {
    case gemini = "com.voiceink.gemini-api-key"
}
```

Leave the rest of `KeychainManager` unchanged.

- [x] **Step 2: Commit**

```bash
git add VoiceInk/Security/KeychainManager.swift
git commit -m "refactor: keychain service for Gemini API key"
```

---

## Phase 2 — WAV encoder (TDD)

### Task 2.1: WAVEncoder

**Files:**
- Create: `VoiceInk/Pipeline/WAVEncoder.swift`
- Test: `VoiceInkTests/WAVEncoderTests.swift`

- [x] **Step 1: Write the failing test**

Create `VoiceInkTests/WAVEncoderTests.swift`:

```swift
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
```

- [x] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project VoiceInk.xcodeproj -scheme VoiceInk -destination 'platform=macOS' -only-testing:VoiceInkTests/WAVEncoderTests -quiet`
Expected: FAIL — "cannot find 'WAVEncoder' in scope".

> If the whole module fails to build because Phase 9 hasn't run, temporarily run only this test target after Task 9; otherwise the encoder file compiles on its own. If module build is red, proceed to write the implementation (Step 3) and defer running until the module is green; mark this checkbox once the test passes after Phase 9. Prefer: implement now, run after Phase 9.

- [x] **Step 3: Write the implementation**

Create `VoiceInk/Pipeline/WAVEncoder.swift`:

```swift
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
```

- [x] **Step 4: Run test (after module is green / Phase 9) to verify it passes**

Run: `xcodebuild test -project VoiceInk.xcodeproj -scheme VoiceInk -destination 'platform=macOS' -only-testing:VoiceInkTests/WAVEncoderTests -quiet`
Expected: PASS.

- [x] **Step 5: Commit**

```bash
git add VoiceInk/Pipeline/WAVEncoder.swift VoiceInkTests/WAVEncoderTests.swift
git commit -m "feat: WAV encoder for 16k mono PCM"
```

---

## Phase 3 — Modes & prompts (TDD)

### Task 3.1: DictationMode + PromptLibrary

**Files:**
- Create: `VoiceInk/Dictation/DictationMode.swift`
- Create: `VoiceInk/Dictation/PromptLibrary.swift`
- Test: `VoiceInkTests/PromptLibraryTests.swift`

- [x] **Step 1: Write the failing test**

Create `VoiceInkTests/PromptLibraryTests.swift`:

```swift
import XCTest
@testable import VoiceInk

final class PromptLibraryTests: XCTestCase {
    func testCleanupPromptMapping() {
        XCTAssertEqual(DictationMode.cleanup.systemPrompt, PromptLibrary.cleanup)
        XCTAssertTrue(PromptLibrary.cleanup.lowercased().contains("final intent"))
        XCTAssertTrue(PromptLibrary.cleanup.lowercased().contains("output only"))
    }

    func testTranslateModeAddsTranslation() {
        let p = DictationMode.translateToEnglish.systemPrompt
        XCTAssertTrue(p.lowercased().contains("translate"))
        XCTAssertTrue(p.lowercased().contains("english"))
    }

    func testAllModesHaveDisplayNames() {
        for mode in DictationMode.allCases {
            XCTAssertFalse(mode.displayName.isEmpty)
        }
    }
}
```

- [x] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project VoiceInk.xcodeproj -scheme VoiceInk -destination 'platform=macOS' -only-testing:VoiceInkTests/PromptLibraryTests -quiet`
Expected: FAIL — "cannot find 'DictationMode'".

- [x] **Step 3: Write the implementations**

Create `VoiceInk/Dictation/DictationMode.swift`:

```swift
import Foundation

enum DictationMode: String, CaseIterable {
    case cleanup
    case translateToEnglish

    var displayName: String {
        switch self {
        case .cleanup: return "Clean Up"
        case .translateToEnglish: return "Translate to English"
        }
    }

    var systemPrompt: String {
        PromptLibrary.prompt(for: self)
    }
}
```

Create `VoiceInk/Dictation/PromptLibrary.swift`:

```swift
import Foundation

enum PromptLibrary {
    static func prompt(for mode: DictationMode) -> String {
        switch mode {
        case .cleanup: return cleanup
        case .translateToEnglish: return translateToEnglish
        }
    }

    static let cleanup = """
    You are a dictation cleanup engine. The provided audio is a person dictating, \
    usually in Korean. Transcribe what they say, then clean it up.

    Rules:
    - Remove filler words, repetitions, false starts, and stutters.
    - If the speaker changes direction mid-sentence, keep ONLY the final intent and \
    discard the abandoned attempt.
    - Fix punctuation and capitalization.
    - When the speech enumerates items or steps, format them as a bullet or numbered list.
    - Keep the original language of the speech.
    - Make the result clean enough to paste directly as a prompt to an AI coding agent.

    Output ONLY the cleaned text. No preamble, no explanation, no markdown code fences.
    """

    static let translateToEnglish = cleanup + """


    After cleaning up, translate the result into natural, polished English and output \
    ONLY the English text.
    """
}
```

- [x] **Step 4: Run test (after module green) to verify it passes**

Run: `xcodebuild test -project VoiceInk.xcodeproj -scheme VoiceInk -destination 'platform=macOS' -only-testing:VoiceInkTests/PromptLibraryTests -quiet`
Expected: PASS.

- [x] **Step 5: Commit**

```bash
git add VoiceInk/Dictation/DictationMode.swift VoiceInk/Dictation/PromptLibrary.swift VoiceInkTests/PromptLibraryTests.swift
git commit -m "feat: dictation modes and prompt library"
```

---

## Phase 4 — SpeechPipeline & GeminiPipeline (TDD)

### Task 4.1: SpeechPipeline protocol + types

**Files:**
- Create: `VoiceInk/Pipeline/SpeechPipeline.swift`

- [x] **Step 1: Write the implementation** (protocol/types have no standalone test; covered by Task 4.2)

Create `VoiceInk/Pipeline/SpeechPipeline.swift`:

```swift
import Foundation

struct RecordedAudio {
    let pcm16: Data      // 16 kHz mono Int16 little-endian
    let sampleRate: Int  // 16000
}

enum PipelineError: LocalizedError, Equatable {
    case missingAPIKey
    case emptyAudio
    case http(Int, String)
    case network(String)
    case decoding(String)
    case noText

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "Gemini API key is not set. Add it in Settings → API Key."
        case .emptyAudio: return "Nothing was recorded."
        case .http(let code, let body): return "Gemini returned HTTP \(code). \(body)"
        case .network(let msg): return "Network error: \(msg)"
        case .decoding(let msg): return "Could not read Gemini response: \(msg)"
        case .noText: return "Gemini returned no text."
        }
    }
}

protocol SpeechPipeline {
    /// Process recorded audio into cleaned text. Throws `PipelineError` on failure.
    func process(_ audio: RecordedAudio, mode: DictationMode) async throws -> String
}
```

- [x] **Step 2: Commit**

```bash
git add VoiceInk/Pipeline/SpeechPipeline.swift
git commit -m "feat: SpeechPipeline protocol and types"
```

### Task 4.2: MockURLProtocol test helper

**Files:**
- Create: `VoiceInkTests/MockURLProtocol.swift`

- [x] **Step 1: Write the helper**

Create `VoiceInkTests/MockURLProtocol.swift`:

```swift
import Foundation

/// Intercepts URLSession requests for tests. Captures the request (with body) and
/// returns a canned response.
final class MockURLProtocol: URLProtocol {
    /// (statusCode, responseBody). Set before each test.
    static var handler: ((URLRequest, Data?) -> (Int, Data))?
    /// Captured request body (httpBodyStream is read into Data here).
    static var lastBody: Data?
    static var lastURL: URL?
    static var lastHeaders: [String: String]?

    static func reset() {
        handler = nil
        lastBody = nil
        lastURL = nil
        lastHeaders = nil
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = MockURLProtocol.readBody(from: request)
        MockURLProtocol.lastBody = body
        MockURLProtocol.lastURL = request.url
        MockURLProtocol.lastHeaders = request.allHTTPHeaderFields

        let (status, data) = MockURLProtocol.handler?(request, body) ?? (500, Data())
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func readBody(from request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }

    /// A URLSession wired to use this protocol.
    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }
}
```

- [x] **Step 2: Commit**

```bash
git add VoiceInkTests/MockURLProtocol.swift
git commit -m "test: add MockURLProtocol helper"
```

### Task 4.3: GeminiPipeline (TDD)

**Files:**
- Create: `VoiceInk/Pipeline/GeminiPipeline.swift`
- Test: `VoiceInkTests/GeminiPipelineTests.swift`

- [x] **Step 1: Write the failing tests**

Create `VoiceInkTests/GeminiPipelineTests.swift`:

```swift
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
```

- [x] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project VoiceInk.xcodeproj -scheme VoiceInk -destination 'platform=macOS' -only-testing:VoiceInkTests/GeminiPipelineTests -quiet`
Expected: FAIL — "cannot find 'GeminiPipeline'".

- [x] **Step 3: Write the implementation**

Create `VoiceInk/Pipeline/GeminiPipeline.swift`:

```swift
import Foundation

// Model ids + latency confirmed by the 2026-05-26 benchmark (13.6s / 103-char Korean
// clip, thinking OFF): gemini-3.5-flash ~2.0s with the best cleanup quality;
// gemini-2.5-flash ~2.7s. The flash-lite tier produced poor cleanup and is excluded.
enum GeminiModel: String, CaseIterable {
    case flash = "gemini-3.5-flash"        // default — best cleanup quality, ~2.0s
    case flashEconomy = "gemini-2.5-flash" // economy — good quality, ~2.7s

    var displayName: String {
        switch self {
        case .flash: return "Gemini 3.5 Flash (recommended)"
        case .flashEconomy: return "Gemini 2.5 Flash (economy)"
        }
    }
}

final class GeminiPipeline: SpeechPipeline {
    private let apiKeyProvider: () -> String?
    private let model: () -> GeminiModel
    private let session: URLSession

    init(apiKeyProvider: @escaping () -> String?,
         model: @escaping () -> GeminiModel,
         session: URLSession = .shared) {
        self.apiKeyProvider = apiKeyProvider
        self.model = model
        self.session = session
    }

    func process(_ audio: RecordedAudio, mode: DictationMode) async throws -> String {
        guard let apiKey = apiKeyProvider(), !apiKey.isEmpty else { throw PipelineError.missingAPIKey }
        guard !audio.pcm16.isEmpty else { throw PipelineError.emptyAudio }

        let wav = WAVEncoder.encode(pcm16: audio.pcm16, sampleRate: audio.sampleRate)
        let base64 = wav.base64EncodedString()

        // thinkingBudget: 0 disables Gemini's reasoning step — the benchmark showed it
        // cuts latency ~4x (and removes 13s spikes) with no quality loss for cleanup.
        let body: [String: Any] = [
            "system_instruction": ["parts": [["text": mode.systemPrompt]]],
            "contents": [[
                "role": "user",
                "parts": [["inline_data": ["mime_type": "audio/wav", "data": base64]]]
            ]],
            "generationConfig": ["thinkingConfig": ["thinkingBudget": 0]]
        ]

        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(model().rawValue):generateContent"
        guard let url = URL(string: urlString) else { throw PipelineError.network("invalid URL") }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        req.timeoutInterval = 60
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw PipelineError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else { throw PipelineError.network("no HTTP response") }
        guard (200..<300).contains(http.statusCode) else {
            let snippet = String(data: data.prefix(300), encoding: .utf8) ?? ""
            throw PipelineError.http(http.statusCode, snippet)
        }
        return try Self.parseText(from: data)
    }

    static func parseText(from data: Data) throws -> String {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw PipelineError.decoding("not JSON")
        }
        guard let candidates = json["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else {
            throw PipelineError.noText
        }
        let text = parts.compactMap { $0["text"] as? String }.joined()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw PipelineError.noText }
        return trimmed
    }
}
```

- [x] **Step 4: Run tests (after module green) to verify they pass**

Run: `xcodebuild test -project VoiceInk.xcodeproj -scheme VoiceInk -destination 'platform=macOS' -only-testing:VoiceInkTests/GeminiPipelineTests -quiet`
Expected: PASS (all 5).

- [x] **Step 5: Commit**

```bash
git add VoiceInk/Pipeline/GeminiPipeline.swift VoiceInkTests/GeminiPipelineTests.swift
git commit -m "feat: Gemini one-call speech pipeline"
```

---

## Phase 5 — Text insertion + AX detection

### Task 5.1: TextInputService rewrite (TDD for pure helper)

**Files:**
- Modify: `VoiceInk/TextInput/TextInputService.swift`
- Test: `VoiceInkTests/TextInputServiceTests.swift`

- [x] **Step 1: Write the failing test for the pure role helper**

Create `VoiceInkTests/TextInputServiceTests.swift`:

```swift
import XCTest
import ApplicationServices
@testable import VoiceInk

final class TextInputServiceTests: XCTestCase {
    func testEditableRoles() {
        XCTAssertTrue(TextInputService.isEditableRole(kAXTextFieldRole as String))
        XCTAssertTrue(TextInputService.isEditableRole(kAXTextAreaRole as String))
        XCTAssertTrue(TextInputService.isEditableRole(kAXComboBoxRole as String))
    }

    func testNonEditableRoles() {
        XCTAssertFalse(TextInputService.isEditableRole(kAXButtonRole as String))
        XCTAssertFalse(TextInputService.isEditableRole(kAXWindowRole as String))
        XCTAssertFalse(TextInputService.isEditableRole(nil))
    }
}
```

- [x] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project VoiceInk.xcodeproj -scheme VoiceInk -destination 'platform=macOS' -only-testing:VoiceInkTests/TextInputServiceTests -quiet`
Expected: FAIL — "type 'TextInputService' has no member 'isEditableRole'".

- [x] **Step 3: Replace `TextInputService.swift`**

```swift
import Cocoa
import ApplicationServices

enum InsertResult: Equatable {
    case pasted
    case copiedToClipboard
}

final class TextInputService {

    /// Pure helper — is this AX role an editable text element?
    static func isEditableRole(_ role: String?) -> Bool {
        guard let role = role else { return false }
        return [
            kAXTextFieldRole as String,
            kAXTextAreaRole as String,
            kAXComboBoxRole as String
        ].contains(role)
    }

    /// Inserts text at the focused editable element, or copies to clipboard if none.
    /// Must be called on the main thread.
    @discardableResult
    func insert(_ text: String) -> InsertResult {
        guard AccessibilityHelper.isGranted else {
            copyToClipboard(text)
            return .copiedToClipboard
        }
        if focusedElementIsEditable() {
            paste(text)
            return .pasted
        }
        copyToClipboard(text)
        return .copiedToClipboard
    }

    // MARK: - Private

    private func focusedElementIsEditable() -> Bool {
        let system = AXUIElementCreateSystemWide()
        var focused: AnyObject?
        let err = AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused)
        guard err == .success, let focused = focused else { return false }
        let element = focused as! AXUIElement

        var roleValue: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
        if Self.isEditableRole(roleValue as? String) { return true }

        var settable: DarwinBoolean = false
        AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable)
        return settable.boolValue
    }

    private func paste(_ text: String) {
        let pasteboard = NSPasteboard.general
        let old = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        pasteboard.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))

        let source = CGEventSource(stateID: .combinedSessionState)
        if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
           let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) {
            keyDown.flags = .maskCommand
            keyUp.flags = .maskCommand
            keyDown.post(tap: .cghidEventTap)
            usleep(10000)
            keyUp.post(tap: .cghidEventTap)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            if let old = old {
                pasteboard.clearContents()
                pasteboard.setString(old, forType: .string)
            }
        }
    }

    /// Leaves result on the clipboard for the user to paste manually (no restore).
    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
```

- [x] **Step 4: Run test (after module green) to verify it passes**

Run: `xcodebuild test -project VoiceInk.xcodeproj -scheme VoiceInk -destination 'platform=macOS' -only-testing:VoiceInkTests/TextInputServiceTests -quiet`
Expected: PASS.

- [x] **Step 5: Commit**

```bash
git add VoiceInk/TextInput/TextInputService.swift VoiceInkTests/TextInputServiceTests.swift
git commit -m "feat: AX-aware text insertion with clipboard fallback"
```

---

## Phase 6 — Result modal (crystal glass)

### Task 6.1: ResultModal view + controller

**Files:**
- Create: `VoiceInk/Views/ResultModal.swift`

- [x] **Step 1: Write the implementation**

Create `VoiceInk/Views/ResultModal.swift`:

```swift
import SwiftUI

struct ResultModalView: View {
    let text: String
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "doc.on.clipboard")
                Text("Copied to clipboard")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
            }
            .foregroundStyle(.secondary)

            ScrollView {
                Text(text)
                    .font(.system(size: 13))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 220)

            HStack {
                Spacer()
                Button("Copy again") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                Button("Close", action: onClose)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 380)
        .background(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.white.opacity(0.18), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.2), radius: 18, y: 6)
    }
}

@MainActor
final class ResultModalController {
    private var window: NSWindow?

    func show(text: String) {
        dismiss()
        let view = ResultModalView(text: text) { [weak self] in self?.dismiss() }
        let hosting = NSHostingView(rootView: view)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 280),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.contentView = hosting
        panel.collectionBehavior = [.canJoinAllSpaces]

        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: f.midX - 190, y: f.midY - 140))
        }
        panel.orderFrontRegardless()
        self.window = panel
    }

    func dismiss() {
        window?.close()
        window = nil
    }
}
```

- [x] **Step 2: Commit**

```bash
git add VoiceInk/Views/ResultModal.swift
git commit -m "feat: crystal-glass result modal for no-cursor fallback"
```

---

## Phase 7 — Multi hotkey

### Task 7.1: HotkeyManager with per-mode bindings

**Files:**
- Modify: `VoiceInk/Hotkey/HotkeyManager.swift`

- [x] **Step 1: Replace `HotkeyManager.swift`**

```swift
import Carbon
import Cocoa

final class HotkeyManager {
    /// Called on the main thread when a registered hotkey fires.
    var onHotkey: ((DictationMode) -> Void)?

    private struct Binding {
        let id: UInt32
        let keyCode: UInt32
        let modifiers: UInt32
        let mode: DictationMode
    }

    private let bindings: [Binding] = [
        Binding(id: 1, keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey), mode: .cleanup),
        Binding(id: 2, keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey | shiftKey), mode: .translateToEnglish)
    ]

    private var refs: [EventHotKeyRef?] = []
    private var idToMode: [UInt32: DictationMode] = [:]
    private var handlerRef: EventHandlerRef?

    init() {
        register()
    }

    deinit {
        refs.forEach { if let r = $0 { UnregisterEventHotKey(r) } }
        if let h = handlerRef { RemoveEventHandler(h) }
    }

    private func register() {
        let signature = OSType(0x564F4943) // "VOIC"
        for b in bindings {
            let hotKeyID = EventHotKeyID(signature: signature, id: b.id)
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(b.keyCode, b.modifiers, hotKeyID,
                                             GetApplicationEventTarget(), 0, &ref)
            if status == noErr {
                refs.append(ref)
                idToMode[b.id] = b.mode
            } else {
                print("Failed to register hotkey \(b.id): \(status)")
            }
        }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))

        let handler: EventHandlerUPP = { _, event, userData -> OSStatus in
            guard let userData = userData, let event = event else {
                return OSStatus(eventNotHandledErr)
            }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()

            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hkID)

            if let mode = manager.idToMode[hkID.id] {
                DispatchQueue.main.async { manager.onHotkey?(mode) }
            }
            return noErr
        }

        InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType,
                            Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
    }
}
```

- [x] **Step 2: Commit** (build still red until AppState refactor)

```bash
git add VoiceInk/Hotkey/HotkeyManager.swift
git commit -m "feat: per-mode global hotkeys (opt+space, shift+opt+space)"
```

---

## Phase 8 — Dictation controller

### Task 8.1: Trim AudioSessionManager to the Int16 path

**Files:**
- Modify: `VoiceInk/Audio/AudioSessionManager.swift`

- [x] **Step 1: Remove the Float32 path**

In `AudioSessionManager.swift`, delete everything related to `onAudioFloat` / `float32Converter` / `AudioFloatHandler` / `convertToFloat32`:
- Remove `typealias AudioFloatHandler` and the `onAudioFloat` / `float32Converter` properties.
- Change `startCapture` to: `func startCapture(onAudioData: @escaping AudioDataHandler)` and set only `self.onAudioData`.
- In `stopCapture`, `startAudioEngine`, `processAudioBuffer`, and `handleConfigurationChange`, remove the float branches and references.
- Delete `convertToFloat32(_:converter:)` entirely.
- In `attemptReconnect`, change the guard to `guard retryCount < maxRetries, onAudioData != nil else { ... }`.

The Int16 capture path (`convertToInt16Data`, reconnection) stays unchanged.

- [x] **Step 2: Commit**

```bash
git add VoiceInk/Audio/AudioSessionManager.swift
git commit -m "refactor: drop unused Float32 capture path"
```

### Task 8.2: DictationController

**Files:**
- Create: `VoiceInk/Dictation/DictationController.swift`

- [x] **Step 1: Write the implementation**

Create `VoiceInk/Dictation/DictationController.swift`:

```swift
import AVFoundation
import Foundation

@MainActor
final class DictationController {
    private let audioManager: AudioSessionManager
    private let pipeline: SpeechPipeline
    private let textInput: TextInputService
    private let history: TranscriptHistoryManager
    private let resultModal: ResultModalController
    private let sampleRate = 16000

    var onStatusChange: ((STTStatus) -> Void)?
    var onAudioLevel: ((Float) -> Void)?
    /// Raised when recording can't start (e.g. missing key / mic denied). Title, message.
    var onError: ((String, String) -> Void)?
    /// Provides the API key presence check before recording.
    var hasAPIKey: () -> Bool = { true }

    private(set) var status: STTStatus = .idle {
        didSet { onStatusChange?(status) }
    }

    private var buffer = Data()
    private var currentMode: DictationMode = .cleanup

    init(audioManager: AudioSessionManager,
         pipeline: SpeechPipeline,
         textInput: TextInputService,
         history: TranscriptHistoryManager,
         resultModal: ResultModalController) {
        self.audioManager = audioManager
        self.pipeline = pipeline
        self.textInput = textInput
        self.history = history
        self.resultModal = resultModal
    }

    func toggle(mode: DictationMode) {
        switch status {
        case .recording: stopAndProcess()
        case .processing: return            // ignore while busy
        default: start(mode: mode)
        }
    }

    var isRecording: Bool { status == .recording }

    // MARK: - Private

    private func start(mode: DictationMode) {
        guard hasAPIKey() else {
            onError?("API Key Required",
                     "A Google AI (Gemini) API key is required.\nGo to Settings → API Key to add it.")
            return
        }
        currentMode = mode
        buffer.removeAll(keepingCapacity: true)

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            beginCapture()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                Task { @MainActor in
                    if granted { self?.beginCapture() } else { self?.status = .idle }
                }
            }
        default:
            onError?("Microphone Access Denied",
                     "Enable microphone access in System Settings → Privacy & Security → Microphone.")
        }
    }

    private func beginCapture() {
        status = .recording
        audioManager.startCapture { [weak self] data in
            guard let self else { return }
            Task { @MainActor in
                self.buffer.append(data)
            }
            self.onAudioLevel?(Self.energy(of: data))
        }
    }

    private func stopAndProcess() {
        audioManager.stopCapture()
        let captured = buffer
        // Ignore very short / empty recordings (< ~0.2s at 16k * 2 bytes/sample).
        guard captured.count > sampleRate * 2 / 5 else {
            status = .idle
            return
        }
        status = .processing
        let mode = currentMode
        let audio = RecordedAudio(pcm16: captured, sampleRate: sampleRate)

        Task { @MainActor in
            do {
                let text = try await pipeline.process(audio, mode: mode)
                let result = textInput.insert(text)
                history.add(text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                            engineType: mode.displayName)
                if result == .copiedToClipboard {
                    resultModal.show(text: text)
                }
                status = .idle
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                status = .error(message)
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                if case .error = status { status = .idle }
            }
        }
    }

    static func energy(of data: Data) -> Float {
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
}
```

> Note: `history.add(text:engineType:)` reuses the existing `TranscriptHistoryManager` signature; we pass the mode display name in the `engineType` label slot. (Renaming that parameter is out of scope.)

- [x] **Step 2: Commit** (build still red until AppState)

```bash
git add VoiceInk/Dictation/DictationController.swift
git commit -m "feat: dictation controller (record buffer to pipeline to insert)"
```

---

## Phase 9 — AppState refactor (module goes green here)

### Task 9.1: Rewrite AppState

**Files:**
- Modify: `VoiceInk/AppState.swift`

- [x] **Step 1: Replace `AppState.swift`**

```swift
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var currentStatus: STTStatus = .idle
    @Published var audioLevel: Float = 0
    @Published var showAlert = false
    @Published var alertMessage = ""

    /// Single source of truth for the model is UserDefaults["geminiModel"], written by
    /// the Settings @AppStorage picker. Read-only convenience for display.
    var geminiModel: GeminiModel {
        GeminiModel(rawValue: UserDefaults.standard.string(forKey: "geminiModel") ?? "") ?? .flash
    }

    private let keychainManager = KeychainManager.shared
    private let audioManager = AudioSessionManager()
    private let textInputService = TextInputService()
    private let soundPlayer = SoundPlayer()
    private let hotkeyManager = HotkeyManager()
    private let overlayController = RecordingOverlayController()
    private let resultModal = ResultModalController()
    let historyManager = TranscriptHistoryManager()
    private var controller: DictationController!

    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    var menuBarIcon: String {
        switch currentStatus {
        case .idle: return "mic.slash"
        case .recording: return "mic.fill"
        case .processing: return "ellipsis.circle"
        case .error: return "exclamationmark.triangle"
        }
    }

    var isRecording: Bool { currentStatus == .recording }

    init() {
        guard !AppState.isRunningTests else { return }

        let pipeline = GeminiPipeline(
            apiKeyProvider: { [keychainManager] in keychainManager.getAPIKey(for: .gemini) },
            model: { GeminiModel(rawValue: UserDefaults.standard.string(forKey: "geminiModel") ?? "") ?? .flash }
        )
        let controller = DictationController(
            audioManager: audioManager,
            pipeline: pipeline,
            textInput: textInputService,
            history: historyManager,
            resultModal: resultModal
        )
        controller.hasAPIKey = { [keychainManager] in keychainManager.hasAPIKey(for: .gemini) }
        controller.onStatusChange = { [weak self] status in
            Task { @MainActor in
                self?.currentStatus = status
                if status == .idle { self?.audioLevel = 0 }
                self?.updateOverlay(for: status)
                if case .error = status { self?.soundPlayer.play(.stop) }
            }
        }
        controller.onAudioLevel = { [weak self] level in
            Task { @MainActor in self?.audioLevel = level }
        }
        controller.onError = { [weak self] title, message in
            Task { @MainActor in self?.showErrorAlert(title: title, message: message) }
        }
        self.controller = controller

        hotkeyManager.onHotkey = { [weak self] mode in
            self?.handleHotkey(mode)
        }

        AccessibilityHelper.requestPermissionIfNeeded()
    }

    func toggle(mode: DictationMode = .cleanup) {
        handleHotkey(mode)
    }

    private func handleHotkey(_ mode: DictationMode) {
        if controller.isRecording {
            soundPlayer.play(.stop)
        } else if currentStatus == .idle {
            soundPlayer.play(.start)
        }
        controller.toggle(mode: mode)
    }

    private func updateOverlay(for status: STTStatus) {
        switch status {
        case .recording, .processing:
            overlayController.show(appState: self)
        case .idle, .error:
            overlayController.dismiss()
        }
    }

    private func showErrorAlert(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "OK")
        if alert.runModal() == .alertFirstButtonReturn {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
    }
}
```

- [x] **Step 2: Build the whole module**

Run: `xcodebuild build -project VoiceInk.xcodeproj -scheme VoiceInk -destination 'platform=macOS' -quiet`
Expected: BUILD SUCCEEDED. If `MenuBarView` / `SettingsView` / `RecordingOverlay` still reference removed symbols (`engineType`, `modelSize`, `.connecting`, `holdToTalk`), they are fixed in Phases 10–11; if the build fails only inside those three view files, proceed to Phase 10/11 then return here. Otherwise fix any AppState compile errors now.

- [x] **Step 3: Commit**

```bash
git add VoiceInk/AppState.swift
git commit -m "refactor: AppState drives DictationController + Gemini, test guard"
```

### Task 9.2: Run the full logic test suite

- [x] **Step 1: Run all tests**

Run: `xcodebuild test -project VoiceInk.xcodeproj -scheme VoiceInk -destination 'platform=macOS' -quiet`
Expected: PASS — WAVEncoderTests, PromptLibraryTests, GeminiPipelineTests, TextInputServiceTests, SmokeTests all green.

> If signing fails for the test bundle, retry with `CODE_SIGNING_ALLOWED=NO` appended.

- [x] **Step 2: Go back and check the deferred test checkboxes** in Tasks 2.1, 3.1, 4.3, 5.1 (their Step 4 "verify it passes") — mark them complete now that the module is green.

---

## Phase 10 — Recording overlay (crystal glass)

### Task 10.1: Waveform + Thinking capsule

**Files:**
- Modify: `VoiceInk/Views/RecordingOverlay.swift`

- [x] **Step 1: Replace `RecordingOverlay.swift`**

```swift
import SwiftUI

struct RecordingOverlayView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        HStack(spacing: 10) {
            switch appState.currentStatus {
            case .recording:
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)
                Waveform(level: appState.audioLevel)
                    .frame(width: 90, height: 18)
            case .processing:
                Text("Thinking…")
                    .font(.system(size: 12, weight: .medium))
                ProgressBarShimmer()
                    .frame(width: 70, height: 4)
            default:
                EmptyView()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial)
        .overlay(
            Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 1)
        )
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.18), radius: 10, y: 3)
    }
}

/// Audio-reactive bars.
private struct Waveform: View {
    var level: Float
    private let bars = 7

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<bars, id: \.self) { i in
                Capsule()
                    .fill(.primary.opacity(0.8))
                    .frame(width: 3, height: barHeight(i))
                    .animation(.easeOut(duration: 0.12), value: level)
            }
        }
    }

    private func barHeight(_ index: Int) -> CGFloat {
        let clamped = min(max(CGFloat(level), 0), 0.15) / 0.15      // 0...1
        // Center bars taller; edges shorter, plus a per-bar phase wobble.
        let center = 1 - abs(CGFloat(index) - CGFloat(bars - 1) / 2) / CGFloat(bars)
        let base: CGFloat = 4
        return base + clamped * 14 * (0.5 + 0.5 * center)
    }
}

/// Indeterminate shimmer bar for the processing state.
private struct ProgressBarShimmer: View {
    @State private var phase: CGFloat = -1

    var body: some View {
        GeometryReader { geo in
            Capsule().fill(.primary.opacity(0.15))
                .overlay(
                    Capsule()
                        .fill(.primary.opacity(0.6))
                        .frame(width: geo.size.width * 0.4)
                        .offset(x: phase * geo.size.width)
                )
                .clipShape(Capsule())
        }
        .onAppear {
            withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                phase = 1.2
            }
        }
    }
}

// MARK: - Overlay Window Controller

@MainActor
final class RecordingOverlayController {
    private var window: NSWindow?

    func show(appState: AppState) {
        guard window == nil else { return }

        let hostingView = NSHostingView(rootView: RecordingOverlayView(appState: appState))
        hostingView.frame = NSRect(x: 0, y: 0, width: 200, height: 44)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 44),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingView
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]

        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: f.midX - 100, y: f.maxY - 70))
        }
        panel.orderFront(nil)
        self.window = panel
    }

    func dismiss() {
        window?.close()
        window = nil
    }
}
```

- [x] **Step 2: Build**

Run: `xcodebuild build -project VoiceInk.xcodeproj -scheme VoiceInk -destination 'platform=macOS' -quiet`
Expected: BUILD SUCCEEDED (overlay no longer references `engineType`/`modelSize`).

- [x] **Step 3: Commit**

```bash
git add VoiceInk/Views/RecordingOverlay.swift
git commit -m "feat: crystal-glass overlay (waveform + thinking shimmer)"
```

---

## Phase 11 — Menu bar & settings

### Task 11.1: MenuBarView

**Files:**
- Modify: `VoiceInk/Views/MenuBarView.swift`

- [x] **Step 1: Replace `MenuBarView.swift`**

```swift
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var appState: AppState
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack {
            Label(statusText, systemImage: statusIcon)

            Divider()

            Button(appState.isRecording ? "Stop" : "Clean Up Dictation") {
                appState.toggle(mode: .cleanup)
            }
            .keyboardShortcut(.space, modifiers: .option)

            Button("Translate to English") {
                appState.toggle(mode: .translateToEnglish)
            }
            .keyboardShortcut(.space, modifiers: [.option, .shift])

            Text("⌥Space clean up · ⇧⌥Space translate")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Divider()

            if !appState.historyManager.entries.isEmpty {
                Text("Recent")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(appState.historyManager.entries.prefix(5)) { entry in
                    Button {
                        appState.historyManager.copyToClipboard(entry)
                    } label: {
                        HStack {
                            Text(entry.preview).lineLimit(1)
                            Spacer()
                            Text(entry.timeAgo).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }

                Button("Clear History") { appState.historyManager.clear() }
                    .foregroundStyle(.secondary)

                Divider()
            }

            Text("Model: \(appState.geminiModel.displayName)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            Button("Settings...") {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            }
            .keyboardShortcut(",")

            Button("Quit VoiceInk") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }

    private var statusText: String {
        switch appState.currentStatus {
        case .idle: return "Idle"
        case .recording: return "Recording"
        case .processing: return "Thinking…"
        case .error(let msg): return "Error: \(msg ?? "Unknown")"
        }
    }

    private var statusIcon: String {
        switch appState.currentStatus {
        case .idle: return "mic.slash"
        case .recording: return "mic.fill"
        case .processing: return "ellipsis.circle"
        case .error: return "exclamationmark.triangle"
        }
    }
}
```

- [x] **Step 2: Build, then commit**

Run: `xcodebuild build -project VoiceInk.xcodeproj -scheme VoiceInk -destination 'platform=macOS' -quiet`
Expected: BUILD SUCCEEDED.

```bash
git add VoiceInk/Views/MenuBarView.swift
git commit -m "feat: menu bar for two dictation modes + Gemini model"
```

### Task 11.2: SettingsView

**Files:**
- Modify: `VoiceInk/Views/SettingsView.swift`

- [x] **Step 1: Replace `SettingsView.swift`**

```swift
import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject var updaterManager: UpdaterManager

    var body: some View {
        TabView {
            GeneralSettingsTab()
                .environmentObject(updaterManager)
                .tabItem { Label("General", systemImage: "gear") }

            ModelSettingsTab()
                .tabItem { Label("Model", systemImage: "cpu") }

            APIKeysSettingsTab()
                .tabItem { Label("API Key", systemImage: "key") }
        }
        .frame(width: 480, height: 320)
    }
}

// MARK: - General

struct GeneralSettingsTab: View {
    @EnvironmentObject var updaterManager: UpdaterManager
    @AppStorage("launchAtLogin") private var launchAtLogin = false

    var body: some View {
        Form {
            Section {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in setLaunchAtLogin(newValue) }
            } header: { Text("Startup") }

            Section {
                LabeledContent("Clean up dictation", value: "⌥ Space")
                LabeledContent("Translate to English", value: "⇧ ⌥ Space")
                Text("Press once to start recording, press again to stop and process.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("Hotkeys") }

            Section {
                LabeledContent("Version",
                    value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0")
                Toggle("Automatically check for updates",
                       isOn: Binding(get: { updaterManager.automaticallyChecksForUpdates },
                                     set: { updaterManager.automaticallyChecksForUpdates = $0 }))
                Button("Check for Updates...") { updaterManager.checkForUpdates() }
                    .disabled(!updaterManager.canCheckForUpdates)
            } header: { Text("About") }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch { print("Failed to set launch at login: \(error)") }
    }
}

// MARK: - Model

struct ModelSettingsTab: View {
    @AppStorage("geminiModel") private var geminiModelRaw = GeminiModel.flash.rawValue

    var body: some View {
        Form {
            Section {
                Picker("Gemini Model", selection: $geminiModelRaw) {
                    ForEach(GeminiModel.allCases, id: \.rawValue) { model in
                        Text(model.displayName).tag(model.rawValue)
                    }
                }
                Text("Audio is transcribed, cleaned up, and (optionally) translated in a single Gemini call. Korean is the primary language.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("Transcription Model") }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - API Key

struct APIKeysSettingsTab: View {
    @State private var apiKey: String = ""
    @State private var hasKey: Bool = false
    @State private var showKey: Bool = false
    @State private var statusMessage: String?

    private let keychainManager = KeychainManager.shared

    var body: some View {
        Form {
            Section {
                HStack {
                    if showKey {
                        TextField("Gemini API Key", text: $apiKey).textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("Gemini API Key", text: $apiKey).textFieldStyle(.roundedBorder)
                    }
                    Button { showKey.toggle() } label: {
                        Image(systemName: showKey ? "eye.slash" : "eye")
                    }.buttonStyle(.borderless)
                }
                HStack {
                    Button("Save") { saveAPIKey() }
                        .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if hasKey {
                        Button("Delete", role: .destructive) { deleteAPIKey() }
                    }
                    Spacer()
                    if let message = statusMessage {
                        Text(message).font(.caption)
                            .foregroundStyle(message.contains("Error") ? .red : .green)
                    }
                }
            } header: { Text("Google AI (Gemini)") } footer: {
                Text("Get a free key at aistudio.google.com → API keys.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear { loadAPIKey() }
    }

    private func loadAPIKey() {
        hasKey = keychainManager.hasAPIKey(for: .gemini)
        if hasKey, let key = keychainManager.getAPIKey(for: .gemini) { apiKey = key }
    }

    private func saveAPIKey() {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try keychainManager.saveAPIKey(trimmed, for: .gemini)
            hasKey = true
            statusMessage = "Saved"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { statusMessage = nil }
        } catch { statusMessage = "Error: \(error.localizedDescription)" }
    }

    private func deleteAPIKey() {
        do {
            try keychainManager.deleteAPIKey(for: .gemini)
            apiKey = ""; hasKey = false; statusMessage = "Deleted"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { statusMessage = nil }
        } catch { statusMessage = "Error: \(error.localizedDescription)" }
    }
}
```

- [x] **Step 2: Build the whole app**

Run: `xcodebuild build -project VoiceInk.xcodeproj -scheme VoiceInk -destination 'platform=macOS' -quiet`
Expected: BUILD SUCCEEDED with no references to `Qwen3ASR`, `STTEngineType`, `STTModelSize`, `holdToTalk`, or `.elevenLabs`.

- [x] **Step 3: Run all tests**

Run: `xcodebuild test -project VoiceInk.xcodeproj -scheme VoiceInk -destination 'platform=macOS' -quiet`
Expected: PASS.

- [x] **Step 4: Commit**

```bash
git add VoiceInk/Views/SettingsView.swift
git commit -m "feat: settings for Gemini model + API key, drop local-model UI"
```

---

## Phase 12 — Manual integration verification

### Task 12.1: End-to-end manual test

**Files:** none (verification only)

- [ ] **Step 1: Confirm model id / endpoint** match current Google AI docs (see caveat at top). If they changed, update `GeminiModel.rawValue` and the URL in `GeminiPipeline`, then rebuild + commit.

- [ ] **Step 2: Build & run the app**

Run: `xcodebuild build -project VoiceInk.xcodeproj -scheme VoiceInk -destination 'platform=macOS' -derivedDataPath .build-run -quiet` then `open .build-run/Build/Products/Debug/VoiceInk.app`

- [ ] **Step 3: First-run setup**
  - Grant Microphone and Accessibility permissions when prompted (System Settings → Privacy & Security).
  - Open Settings → API Key, paste a Gemini key, Save.

- [ ] **Step 4: Verify cleanup mode**
  - Focus a text field (e.g. Notes or a browser input).
  - Press ⌥Space → glass capsule shows the live waveform.
  - Speak a rambling Korean sentence with a self-correction.
  - Press ⌥Space → capsule shows "Thinking…" → cleaned text is pasted at the cursor; verify the original clipboard is restored.

- [ ] **Step 5: Verify translate mode**
  - Press ⇧⌥Space, speak Korean, press ⇧⌥Space again → polished English is pasted.

- [ ] **Step 6: Verify no-cursor fallback**
  - Click the desktop (no editable field focused).
  - Press ⌥Space, speak, press ⌥Space → the crystal-glass result modal appears with the text and "Copied to clipboard"; Cmd+V into any field works.

- [ ] **Step 7: Verify error handling**
  - Delete the API key in Settings, press ⌥Space → "API Key Required" alert with Open Settings.
  - With a key set but network off, record briefly → error status shown, clipboard untouched.

- [ ] **Step 8: Note any proper-noun / number mis-transcriptions** across ~5–10 real Korean clips. If accuracy is unacceptable, the spec's fallback is a future 2-step pipeline (out of scope here) — record findings in the PR description.

- [ ] **Step 9: Final commit / branch wrap-up** (any fixes from manual testing)

```bash
git add -A && git commit -m "fix: address manual verification findings"
```

---

## Self-Review Notes (author)

- **Spec coverage:** batch Gemini one-call (Task 4.3), swappable `SpeechPipeline` (4.1), toggle recording (8.2/9.1), two modes + prompts (3.1, 7.1), cursor insert + clipboard modal fallback (5.1, 6.1, 8.2), crystal-glass overlay waveform/Thinking (10.1), Gemini API key + model settings (1.2, 11.2), keep VoiceInk name/bundle (no rename task — intentional), remove local models/ElevenLabs (0.1, 1.x). All spec sections map to a task.
- **Out of scope (per spec §13):** realtime, 2-step pipeline implementation, custom modes/dictionary, raw transcript exposure, rename — none included.
- **Type consistency:** `RecordedAudio.pcm16`, `PipelineError` cases, `SpeechPipeline.process(_:mode:)`, `GeminiModel.flash`, `DictationMode.cleanup/.translateToEnglish`, `TextInputService.isEditableRole`/`insert`, `InsertResult.pasted/.copiedToClipboard`, `HotkeyManager.onHotkey`, `DictationController.toggle(mode:)`, `STTStatus.processing` — referenced consistently across tasks.
- **Build-order caveat:** the module is intentionally red from Phase 1 until Phase 9; logic-test "verify pass" steps are deferred and re-checked in Task 9.2 Step 2.
