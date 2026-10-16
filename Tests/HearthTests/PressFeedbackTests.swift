import XCTest
@testable import Hearth

final class PressFeedbackTests: XCTestCase {
    func testReduceMotionKeepsPressedButtonsAtTheirOriginalSize() {
        XCTAssertEqual(PressFeedback.scale(pressed: true, reduceMotion: true), 1)
        XCTAssertEqual(PressFeedback.scale(pressed: false, reduceMotion: true), 1)
    }

    func testNormalPressFeedbackRemainsAvailable() {
        XCTAssertEqual(PressFeedback.scale(pressed: true, reduceMotion: false), 0.965)
        XCTAssertEqual(PressFeedback.scale(pressed: false, reduceMotion: false), 1)
    }
}
