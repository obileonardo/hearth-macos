import XCTest
@testable import Hearth

final class ClimateCommandTests: XCTestCase {
    private var entity: Entity {
        Entity(id: "climate.fixture_ac", state: "cool", attributes: [
            "hvac_modes": ["off", "cool", "auto", "dry", "fan_only"],
            "temperature": 24.0, "min_temp": 16.0, "max_temp": 30.0
        ])
    }
    func testEveryAdvertisedRequestedModeUsesCanonicalHomeAssistantValue() throws {
        for mode in ["auto", "dry", "fan_only"] {
            let action = try XCTUnwrap(ClimateCommand.mode(entity, requested: mode))
            XCTAssertEqual(action.domain, "climate")
            XCTAssertEqual(action.service, "set_hvac_mode")
            XCTAssertEqual(action.entityID, entity.id)
            XCTAssertEqual(action.data["hvac_mode"] as? String, mode)
        }
    }
    func testAlreadyReportedAndUnsupportedModesAreNotSent() {
        XCTAssertNil(ClimateCommand.mode(entity, requested: "cool"))
        XCTAssertNil(ClimateCommand.mode(entity, requested: "heat"))
    }
    func testUnavailableAndNonClimateEntitiesCannotBeControlled() {
        var unavailable = entity
        unavailable.state = "unavailable"
        XCTAssertNil(ClimateCommand.mode(unavailable, requested: "auto"))
        XCTAssertNil(ClimateCommand.temperature(unavailable, value: 24))
        let other = Entity(id: "switch.fixture", state: "on", attributes: entity.attributes)
        XCTAssertNil(ClimateCommand.mode(other, requested: "auto"))
        XCTAssertNil(ClimateCommand.temperature(other, value: 24))
    }
    func testOffEntityCanSelectAnAdvertisedOnMode() {
        var off = entity
        off.state = "off"
        XCTAssertNotNil(ClimateCommand.mode(off, requested: "cool"))
    }
    func testTemperatureUsesCurrentBoundsAndRejectsInvalidNumbers() throws {
        for target in [16.0, 24.5, 30.0] {
            let action = try XCTUnwrap(ClimateCommand.temperature(entity, value: target))
            XCTAssertEqual(action.data["temperature"] as? Double, target)
        }
        for target in [15.5, 30.5, Double.nan, Double.infinity, -Double.infinity] {
            XCTAssertNil(ClimateCommand.temperature(entity, value: target))
        }
    }
    func testModeWithNoSetpointCannotReceiveAPhantomTemperature() {
        var fan = entity
        fan.state = "fan_only"
        fan.attributes.removeValue(forKey: "temperature")
        XCTAssertNil(ClimateCommand.temperature(fan, value: 16))
        XCTAssertNil(Climate(e: fan).target)
    }
    func testCommandPlanningNeverMutatesReportedState() {
        let reported = entity
        _ = ClimateCommand.mode(reported, requested: "dry")
        _ = ClimateCommand.temperature(reported, value: 26)
        XCTAssertEqual(reported.state, "cool")
        XCTAssertEqual(reported.num("temperature"), 24)
    }
}
