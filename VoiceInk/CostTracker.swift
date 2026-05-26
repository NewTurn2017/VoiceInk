import Foundation

@MainActor
final class CostTracker: ObservableObject {
    static let shared = CostTracker()

    @Published private(set) var totalCostUSD: Double
    @Published private(set) var audioInputTokens: Int
    @Published private(set) var textInputTokens: Int
    @Published private(set) var outputTokens: Int
    @Published private(set) var callCount: Int

    private let defaults = UserDefaults.standard
    private enum Key {
        static let cost = "usageTotalCostUSD"
        static let audio = "usageAudioInputTokens"
        static let text = "usageTextInputTokens"
        static let output = "usageOutputTokens"
        static let calls = "usageCallCount"
    }

    private init() {
        totalCostUSD = defaults.double(forKey: Key.cost)
        audioInputTokens = defaults.integer(forKey: Key.audio)
        textInputTokens = defaults.integer(forKey: Key.text)
        outputTokens = defaults.integer(forKey: Key.output)
        callCount = defaults.integer(forKey: Key.calls)
    }

    func record(usage: TokenUsage, model: GeminiModel) {
        let cost = Double(usage.audioInputTokens) / 1_000_000 * model.audioInputPricePerM
                 + Double(usage.textInputTokens)  / 1_000_000 * model.textInputPricePerM
                 + Double(usage.outputTokens)     / 1_000_000 * model.outputPricePerM
        totalCostUSD += cost
        audioInputTokens += usage.audioInputTokens
        textInputTokens += usage.textInputTokens
        outputTokens += usage.outputTokens
        callCount += 1
        persist()
    }

    func reset() {
        totalCostUSD = 0; audioInputTokens = 0; textInputTokens = 0; outputTokens = 0; callCount = 0
        persist()
    }

    private func persist() {
        defaults.set(totalCostUSD, forKey: Key.cost)
        defaults.set(audioInputTokens, forKey: Key.audio)
        defaults.set(textInputTokens, forKey: Key.text)
        defaults.set(outputTokens, forKey: Key.output)
        defaults.set(callCount, forKey: Key.calls)
    }
}
