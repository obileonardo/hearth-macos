import XCTest
@testable import Hearth

final class ActivityPresentationTests: XCTestCase {
    func testClimateCategoryUsesSnowflake() {
        XCTAssertEqual(ActivityLog.Kind.climate.symbol, "snowflake")
    }

    func testClimateEventUsesAdvertisedDeviceCapabilities() {
        let ac = Entity(id: "climate.fixture", state: "cool", attributes: ["hvac_modes": ["off", "cool", "heat"]])
        let heater = Entity(id: "climate.fixture", state: "heat", attributes: ["hvac_modes": ["off", "heat"]])
        let sensor = Entity(id: "sensor.fixture", state: "24", attributes: ["device_class": "temperature"])
        XCTAssertEqual(ActivityEventPresentation.symbol(kind: .climate, entity: ac), "air.conditioner.horizontal.fill")
        XCTAssertEqual(ActivityEventPresentation.symbol(kind: .climate, entity: heater), "heater.vertical.fill")
        XCTAssertEqual(ActivityEventPresentation.symbol(kind: .climate, entity: sensor), "thermometer.medium")
        XCTAssertEqual(ActivityEventPresentation.climateLabel(heater), "heating")
        XCTAssertEqual(ActivityEventPresentation.climateLabel(ac), "AC")
    }

    func testUnknownDeviceAndProblemDoNotPretendToBeAirConditioners() {
        XCTAssertEqual(ActivityEventPresentation.symbol(kind: .climate, entity: nil), "thermometer.medium")
        let problem = Entity(id: "binary_sensor.fixture", state: "on", attributes: ["device_class": "problem"])
        XCTAssertEqual(ActivityEventPresentation.symbol(kind: .climate, entity: problem), "exclamationmark.triangle.fill")
    }

    func testEmptyMessageMatchesSelectedCategory() {
        XCTAssertTrue(ActivityEventPresentation.emptyMessage(for: .climate).contains("heating"))
        XCTAssertFalse(ActivityEventPresentation.emptyMessage(for: .climate).contains("doorbell"))
        XCTAssertTrue(ActivityEventPresentation.emptyMessage(for: .motion).contains("Motion"))
    }
}
