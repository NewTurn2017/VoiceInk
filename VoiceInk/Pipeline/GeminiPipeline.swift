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
