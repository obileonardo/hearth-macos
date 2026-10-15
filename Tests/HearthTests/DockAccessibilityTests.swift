import XCTest
@testable import Hearth

final class DockAccessibilityTests: XCTestCase {
    func testBadgeAnnouncesCompleteCountAndCorrectPlural() {
        XCTAssertEqual(DockAccessibility.badgeValue(1), "1 unread notification")
        XCTAssertEqual(DockAccessibility.badgeValue(7), "7 unread notifications")
        XCTAssertEqual(DockAccessibility.badgeValue(12), "12 unread notifications")
    }

    func testEmptyAndInvalidBadgeCountsDoNotAnnounceUnreadItems() {
        XCTAssertEqual(DockAccessibility.badgeValue(0), "")
        XCTAssertEqual(DockAccessibility.badgeValue(-1), "")
    }
}
