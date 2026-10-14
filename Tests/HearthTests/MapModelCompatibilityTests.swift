import Foundation
import XCTest
@testable import Hearth

final class MapModelCompatibilityTests: XCTestCase {
    func testLegacyPinWithoutFloorRemainsOnGroundFloor() throws {
        let data = Data(#"{"id":"device-1","name":"Kitchen speaker","kind":"smartSpeaker","x":1.5,"y":0.4,"z":-2.25}"#.utf8)
        let pin = try JSONDecoder().decode(MapPin.self, from: data)
        XCTAssertNil(pin.floor)
        XCTAssertEqual(pin.level, 0)
        XCTAssertEqual(pin.position, SIMD3<Float>(1.5, 0.4, -2.25))
        XCTAssertEqual(pin.art, .smartSpeaker)
    }

    func testUnknownDeviceKindKeepsIdentityCoordinatesAndRawKind() throws {
        let original = MapPin(id: "future-device", name: "Future device", kind: "new-device-kind",
                              x: 2.2, y: 0.7, z: -3.4, floor: 2)
        let restored = try JSONDecoder().decode(MapPin.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(restored, original)
        XCTAssertEqual(restored.art, .generic)
        XCTAssertEqual(restored.kind, "new-device-kind")
        XCTAssertEqual(restored.level, 2)
    }

    func testGroundUpperAndBasementPinsRoundTripWithoutRepositioning() throws {
        let levels: [Int] = [-2, -1, 0, 1, 2]
        let pins = levels.map {
            MapPin(id: "gadget:\($0)", name: "Saved device", kind: "fridge",
                   x: 1.25, y: 0.9, z: -2.5, floor: $0)
        }
        let restored = try JSONDecoder().decode([MapPin].self, from: JSONEncoder().encode(pins))
        XCTAssertEqual(restored, pins)
        XCTAssertEqual(restored.map(\.level), [-2, -1, 0, 1, 2])
    }

    func testDemoPrefixDoesNotConfuseRealDeviceIdentifiers() {
        let demo = MapPin(id: "demo:fridge", name: "Fridge", kind: "fridge", x: 0, y: 0, z: 0)
        var real = demo
        real.id = "device-demo-fridge"
        XCTAssertTrue(demo.isDemo)
        XCTAssertFalse(real.isDemo)
    }

    func testFloorNamesIncludeUpperFloorsAndBasements() {
        XCTAssertEqual(MapFloor.defaultName(-2), "Basement 2")
        XCTAssertEqual(MapFloor.defaultName(-1), "Basement")
        XCTAssertEqual(MapFloor.defaultName(0), "Ground")
        XCTAssertEqual(MapFloor.defaultName(1), "First")
        XCTAssertEqual(MapFloor.defaultName(2), "Second")
        XCTAssertEqual(MapFloor.defaultName(3), "Third")
        XCTAssertEqual(MapFloor.defaultName(4), "Floor 4")
    }

    func testRenamedFloorAndScanReferenceRoundTripWithoutChange() throws {
        let original = MapFloor(level: 2, name: "Master bedroom floor", scan: "upper-floor.usdz")
        let restored = try JSONDecoder().decode(MapFloor.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(restored, original)
        XCTAssertEqual(restored.id, 2)
    }
}
