import Foundation

// Model ids + latency confirmed against the live API on 2026-10-15 (12.6s Korean clip,
// minimal reasoning): gemini-3.8-flash ~2.5s with the best cleanup quality;
// gemini-2.5-flash ~2.9s. The flash-lite tier produced poor cleanup in the 2026-05-26
// benchmark and is excluded.
enum GeminiModel: String, CaseIterable {
    case flash = "gemini-3.8-flash"        // default — best cleanup quality, ~2.5s
    case flashEconomy = "gemini-2.5-flash" // economy — good quality, ~2.9s

    var displayName: String {
        switch self {
        case .flash: return "Gemini 3.8 Flash (recommended)"
        case .flashEconomy: return "Gemini 2.5 Flash (economy)"
        }
    }

    /// Keeps Gemini's reasoning step to a minimum — it cuts latency several-fold (and removes
    /// 13s spikes) with no quality loss for cleanup. 3.8 Flash can't turn thinking off and takes
    /// a level instead (default medium took ~6.7s vs ~2.5s at low); 2.5 Flash takes a budget, 0 = off.
    var thinkingConfig: [String: Any] {
        switch self {
        case .flash: return ["thinkingLevel": "low"]
        case .flashEconomy: return ["thinkingBudget": 0]
        }
    }

    /// The currently selected model from UserDefaults["geminiModel"], defaulting to `.flash`.
    static var current: GeminiModel {
        GeminiModel(rawValue: UserDefaults.standard.string(forKey: "geminiModel") ?? "") ?? .flash
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

    func process(_ audio: RecordedAudio, mode: DictationMode) async throws -> PipelineResult {
        guard let apiKey = apiKeyProvider(), !apiKey.isEmpty else { throw PipelineError.missingAPIKey }
        guard !audio.pcm16.isEmpty else { throw PipelineError.emptyAudio }

        let model = self.model()
        let wav = WAVEncoder.encode(pcm16: audio.pcm16, sampleRate: audio.sampleRate)
        let base64 = wav.base64EncodedString()

        let body: [String: Any] = [
            "system_instruction": ["parts": [["text": mode.systemPrompt]]],
            "contents": [[
                "role": "user",
                "parts": [["inline_data": ["mime_type": "audio/wav", "data": base64]]]
            ]],
            "generationConfig": ["thinkingConfig": model.thinkingConfig]
        ]

        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(model.rawValue):generateContent"
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
        return try Self.parseResult(from: data)
    }

    static func parseResult(from data: Data) throws -> PipelineResult {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw PipelineError.decoding("not JSON")
        }
        guard let candidates = json["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else {
            throw PipelineError.noText
        }
        let text = parts.compactMap { $0["text"] as? String }.joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw PipelineError.noText }
        return PipelineResult(text: text, usage: parseUsage(from: json))
    }

    static func parseUsage(from json: [String: Any]) -> TokenUsage? {
        guard let meta = json["usageMetadata"] as? [String: Any] else { return nil }
        let promptTotal = meta["promptTokenCount"] as? Int ?? 0
        // Thinking tokens are billed at the output rate.
        let output = (meta["candidatesTokenCount"] as? Int ?? 0) + (meta["thoughtsTokenCount"] as? Int ?? 0)
        var audio = 0, text = 0
        if let details = meta["promptTokensDetails"] as? [[String: Any]] {
            for d in details {
                let count = d["tokenCount"] as? Int ?? 0
                switch (d["modality"] as? String)?.uppercased() {
                case "AUDIO": audio += count
                case "TEXT":  text += count
                default:      text += count
                }
            }
        }
        if audio == 0 && text == 0 { audio = promptTotal } // no breakdown → attribute to audio (conservative)
        return TokenUsage(audioInputTokens: audio, textInputTokens: text, outputTokens: output)
    }
}

// Paid-tier USD per 1M tokens (ai.google.dev/gemini-api/docs/pricing, checked 2026-10-15).
// 3.8 Flash bills audio and text input alike.
extension GeminiModel {
    var audioInputPricePerM: Double { switch self { case .flash: return 1.50 * Self.launchDiscount(); case .flashEconomy: return 1.00 } }
    var textInputPricePerM: Double  { switch self { case .flash: return 1.50 * Self.launchDiscount(); case .flashEconomy: return 0.30 } }
    var outputPricePerM: Double     { switch self { case .flash: return 7.50 * Self.launchDiscount(); case .flashEconomy: return 2.50 } }

    /// 3.8 Flash is billed at half its list price through 2026-12-31.
    static func launchDiscount(on date: Date = Date()) -> Double {
        date < Date(timeIntervalSince1970: 1_798_761_600) ? 0.5 : 1.0 // 2027-01-01 00:00 UTC
    }
}
