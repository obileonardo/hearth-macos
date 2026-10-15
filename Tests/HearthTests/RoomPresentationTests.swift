import Foundation
import XCTest
@testable import Hearth

final class RoomPresentationTests: XCTestCase {
    private func device(_ entities: [Entity]) -> HomeDevice {
        HomeDevice(info: DeviceInfo(id: "fixture", name: "Room fixture", manufacturer: nil,
                                    model: nil, areaID: "fixture-room"), entities: entities)
    }

    func testNormalReadingsKeepRoundedDegreePresentation() {
        XCTAssertEqual(RoomPresentation.temperature(24.2), "24°")
        XCTAssertEqual(RoomPresentation.temperature(24.5), "25°")
        XCTAssertEqual(RoomPresentation.temperature(-3.6), "-4°")
        XCTAssertEqual(RoomPresentation.temperature(0), "0°")
    }

    func testInvalidAndOutOfRangeNumbersHaveNoDisplayReading() {
        for value in [Double.nan, Double.infinity, -Double.infinity, Double.greatestFiniteMagnitude,
                      -Double.greatestFiniteMagnitude, Double(Int.max), -Double(Int.max) * 2] {
            XCTAssertNil(RoomPresentation.temperature(value))
        }
        XCTAssertNil(RoomPresentation.temperature(nil))
    }

    func testValidClimateReadingTakesPriorityOverSensor() {
        let sensor = Entity(id: "sensor.room", state: "20", attributes: ["device_class": "temperature"])
        let climate = Entity(id: "climate.room", state: "cool", attributes: ["current_temperature": 23.6])
        XCTAssertEqual(RoomPresentation.temperature(in: [device([sensor, climate])]), "24°")
    }

    func testMalformedClimateAndSensorContinueToValidSensor() {
        let climate = Entity(id: "climate.room", state: "cool", attributes: ["current_temperature": "NaN"])
        let invalid = Entity(id: "sensor.invalid", state: "inf", attributes: ["device_class": "temperature"])
        let valid = Entity(id: "sensor.valid", state: "21.4", attributes: ["device_class": "temperature"])
        XCTAssertEqual(RoomPresentation.temperature(in: [device([climate, invalid, valid])]), "21°")
    }

    func testMalformedClimateContinuesToNextClimateBeforeSensor() {
        let invalid = Entity(id: "climate.invalid", state: "cool", attributes: ["current_temperature": "1e300"])
        let valid = Entity(id: "climate.valid", state: "cool", attributes: ["current_temperature": 22.8])
        let sensor = Entity(id: "sensor.room", state: "20", attributes: ["device_class": "temperature"])
        XCTAssertEqual(RoomPresentation.temperature(in: [device([invalid, valid, sensor])]), "23°")
    }

    func testNoValidTemperatureDoesNotInventAReading() {
        XCTAssertNil(RoomPresentation.temperature(in: []))
        XCTAssertNil(RoomPresentation.temperature(in: [device([
            Entity(id: "sensor.temperature", state: "unknown", attributes: ["device_class": "temperature"]),
            Entity(id: "sensor.other", state: "12", attributes: ["device_class": "humidity"])
        ])]))
    }

    func testEmptyRoomCopyUsesRoomNameAndHasUnassignedFallback() {
        XCTAssertEqual(RoomPresentation.emptyRoomMessage(name: " Guest room "),
                       "Assign a device to Guest room in Home Assistant to show it here.")
        let fallback = "Devices without a room assignment in Home Assistant will appear here."
        XCTAssertEqual(RoomPresentation.emptyRoomMessage(name: nil), fallback)
        XCTAssertEqual(RoomPresentation.emptyRoomMessage(name: "  \n"), fallback)
    }
}
