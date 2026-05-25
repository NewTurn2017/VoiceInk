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
