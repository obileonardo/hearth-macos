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
    func testFractionalStepsAreNotClampedToHalfADegree() {
        var fine = entity
        fine.attributes["target_temp_step"] = 0.1
        XCTAssertEqual(Climate(e: fine).step, 0.1)
        fine.attributes["target_temp_step"] = 0.25
        XCTAssertEqual(Climate(e: fine).step, 0.25)
        XCTAssertEqual(degrees(24.25), "24.25")
    }

    func testInvalidStepUsesSafeDefaultWithoutChangingAdvertisedModes() {
        for invalid in [0.0, -1, Double.nan, Double.infinity] {
            var invalidEntity = entity
            invalidEntity.attributes["target_temp_step"] = invalid
            XCTAssertEqual(Climate(e: invalidEntity).step, 1)
            XCTAssertEqual(Climate(e: invalidEntity).modes.count, 4)
        }
    }

    func testMalformedTemperatureBoundsDoNotConstructASliderOrCommand() {
        for (low, high) in [(30.0, 16.0), (.nan, 30), (16, .infinity), (-Double.greatestFiniteMagnitude, Double.greatestFiniteMagnitude)] {
            var invalidEntity = entity
            invalidEntity.attributes["min_temp"] = low
            invalidEntity.attributes["max_temp"] = high
            XCTAssertNil(Climate(e: invalidEntity).temperatureRange)
            XCTAssertNil(ClimateCommand.temperature(invalidEntity, value: 24))
        }
    }

    func testNonFiniteSetpointAndRoomAreUnavailableRatherThanFormatted() {
        for invalid in [Double.nan, Double.infinity, -Double.infinity] {
            var invalidEntity = entity
            invalidEntity.attributes["temperature"] = invalid
            invalidEntity.attributes["current_temperature"] = invalid
            invalidEntity.attributes["supported_features"] = invalid
            XCTAssertNil(Climate(e: invalidEntity).target)
            XCTAssertNil(Climate(e: invalidEntity).room)
            XCTAssertFalse(Climate(e: invalidEntity).canTurnOn)
            XCTAssertNil(ClimateCommand.temperature(invalidEntity, value: 24))
            XCTAssertEqual(degrees(invalid), "—")
        }
    }

    func testSnappingUsesAdvertisedLowerBoundAndNeverEscapesRange() {
        let range = 16.2...30.4
        XCTAssertEqual(ClimateTemperatureScale.snapped(17.16, range: range, step: 0.5), 17.2, accuracy: 0.00001)
        XCTAssertEqual(ClimateTemperatureScale.snapped(100, range: range, step: 0.5), 30.4)
        XCTAssertEqual(ClimateTemperatureScale.snapped(-100, range: range, step: 0.5), 16.2)
        for target in stride(from: 16.2, through: 30.4, by: 0.01) {
            XCTAssertTrue(range.contains(ClimateTemperatureScale.snapped(target, range: range, step: 0.5)))
        }
    }

    func testFixedAndNarrowTemperatureRangesKeepTheirEndpoints() {
        XCTAssertEqual(ClimateTemperatureScale.snapped(25, range: 24...24, step: 1), 24)
        XCTAssertEqual(ClimateTemperatureScale.snapped(25, range: 24...24.4, step: 1), 24.4)
        XCTAssertEqual(ClimateTemperatureScale.snapped(.nan, range: 24...24.4, step: 1), 24)
    }

}
