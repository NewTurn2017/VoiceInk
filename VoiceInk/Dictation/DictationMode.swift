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
