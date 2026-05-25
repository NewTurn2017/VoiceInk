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
