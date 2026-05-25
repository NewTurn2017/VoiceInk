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
