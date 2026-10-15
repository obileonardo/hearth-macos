import XCTest
@testable import Hearth

final class HeadingAccessibilityTests: XCTestCase {
    func testOriginalAndFloatingHeadingHaveOneOwnerThroughoutHandoff() {
        for step in 0...100 {
            let progress = CGFloat(step) / 100
            let floating = HeadingAccessibility.usesFloatingHeading(progress: progress)
            let original = !floating
            XCTAssertEqual([original, floating].filter { $0 }.count, 1)
            XCTAssertEqual(floating, step >= 50)
        }
    }

    func testInvalidGeometryKeepsOriginalHeadingAvailable() {
        for value: CGFloat in [.nan, .infinity, -.infinity] {
            XCTAssertFalse(HeadingAccessibility.usesFloatingHeading(progress: value))
        }
    }

    func testHeadingLabelKeepsTitleBeforeSummaryWithoutEmptyPunctuation() {
        XCTAssertEqual(HeadingAccessibility.label(title: "Security", summary: "7 cameras"), "Security, 7 cameras")
        XCTAssertEqual(HeadingAccessibility.label(title: " Settings ", summary: " \n"), "Settings")
        XCTAssertEqual(HeadingAccessibility.label(title: "", summary: "Home"), "Home")
    }

    func testSupportAndNotificationDecorationsMatchTheirDestinations() {
        XCTAssertEqual(SubpageHeadingSymbols.resolve(eyebrow: "Settings", title: "Help & Support"),
                       ["lifepreserver", "envelope", "ladybug"])
        XCTAssertEqual(SubpageHeadingSymbols.resolve(eyebrow: "Help & Support", title: "Report a bug"),
                       ["ladybug", "envelope"])
        XCTAssertEqual(SubpageHeadingSymbols.resolve(eyebrow: "Help & Support", title: "Get help"),
                       ["lifepreserver", "envelope"])
        XCTAssertEqual(SubpageHeadingSymbols.resolve(eyebrow: "Activity", title: "Notifications"),
                       ["bell", "slider.horizontal.3"])
    }

    func testAccountFacesAndHomeDecorationsDoNotImplyRoomControls() {
        XCTAssertEqual(SubpageHeadingSymbols.resolve(eyebrow: "Settings", title: "Account"),
                       ["person.crop.circle", "server.rack", "network"])
        XCTAssertEqual(SubpageHeadingSymbols.resolve(eyebrow: "3 familiar faces", title: "Familiar faces"),
                       ["person.crop.circle", "person.2"])
        XCTAssertEqual(SubpageHeadingSymbols.resolve(eyebrow: "Demo home", title: "Sample home"), ["house", "bolt"])
        XCTAssertEqual(SubpageHeadingSymbols.resolve(eyebrow: "Device", title: "Unknown"), ["square.grid.2x2"])
    }
}
