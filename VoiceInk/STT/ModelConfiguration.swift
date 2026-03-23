import Foundation

enum STTModelSize: String, CaseIterable {
    case small = "aufklarer/Qwen3-ASR-0.6B-MLX-4bit"
    case large = "mlx-community/Qwen3-ASR-1.7B-4bit"

    var displayName: String {
        switch self {
        case .small: return "Qwen3-ASR 0.6B (Fast, ~675MB)"
        case .large: return "Qwen3-ASR 1.7B (Accurate, ~1.6GB)"
        }
    }
}

enum STTEngineType: String, CaseIterable {
    case local
    case cloud

    var displayName: String {
        switch self {
        case .local: return "Local (Offline)"
        case .cloud: return "Cloud (ElevenLabs)"
        }
    }
}
