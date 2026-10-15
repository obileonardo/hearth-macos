import XCTest
@testable import Hearth

final class SpeakerTemperatureSafetyTests: XCTestCase {
    private func speaker(_ value: String) -> HomeDevice {
        HomeDevice(info: DeviceInfo(id: "fixture", name: "Office", manufacturer: "Amazon", model: "Echo Dot", areaID: nil),
                   entities: [Entity(id: "sensor.office_temperature", state: value, attributes: ["device_class": "temperature", "unit_of_measurement": "°C"])])
    }
    func testNormalSpeakerTemperatureKeepsItsUnitAndRounding() {
        XCTAssertEqual(speaker("23.7").summary, "24°C")
    }
    func testMalformedSpeakerTemperaturesFallBackToReady() {
        for value in ["NaN", "inf", "-inf", "1e300", "unknown"] {
            XCTAssertEqual(speaker(value).summary, "Ready")
        }
    }
}
