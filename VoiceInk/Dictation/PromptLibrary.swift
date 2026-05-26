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
    - If the audio has no discernible speech (only silence or background noise), \
    output an empty string and nothing else. Never invent or guess content.

    Output ONLY the cleaned text. No preamble, no explanation, no markdown code fences.
    """

    static let translateToEnglish = cleanup + """


    After cleaning up, translate the result into natural, polished English and output \
    ONLY the English text.
    """
}
