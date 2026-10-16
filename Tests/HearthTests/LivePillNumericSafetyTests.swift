import XCTest
@testable import Hearth

final class LivePillNumericSafetyTests: XCTestCase {
    func testNormalNotificationTemperatureRoundingStaysUnchanged() {
        XCTAssertEqual(LivePillClimateReading.text(24), "24")
        XCTAssertEqual(LivePillClimateReading.text(24.5), "24.5")
        XCTAssertEqual(LivePillClimateReading.text(24.25), String(format: "%.1f", 24.25))
        XCTAssertEqual(LivePillClimateReading.text(-2), "-2")
        XCTAssertEqual(LivePillClimateReading.text(0), "0")
    }

    func testNonfiniteAndFiniteOutOfIntegerRangeNeverBecomeNotificationText() {
        for value in [Double.nan, .infinity, -.infinity, .greatestFiniteMagnitude,
                      -.greatestFiniteMagnitude, 1e300, -1e300, Double(Int.max)] {
            XCTAssertNil(LivePillClimateReading.text(value))
        }
    }

    func testFiniteHeatingThresholdCrossingCannotTrapTheNotificationFormatter() {
        let old = Entity(id: "climate.fixture", state: "heat", attributes: ["temperature": 1e300, "current_temperature": 0])
        let new = Entity(id: old.id, state: "heat", attributes: ["temperature": 1e300, "current_temperature": 1e300])
        let before = Climate(e: old), reported = Climate(e: new)
        let target = reported.target!
        XCTAssertTrue(before.room! < target && reported.room! >= target)
        XCTAssertNil(LivePillClimateReading.text(target))
    }
}
