import Foundation
import CoreGraphics
import XCTest
@testable import Hearth

final class WidgetSnapshotTests: XCTestCase {
    private func storage() throws -> HearthWidgetStore {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("HearthWidgetTests-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return HearthWidgetStore(folder: folder)
    }

    func testSnapshotRoundTripAndAtomicReplacement() throws {
        let store = try storage()
        var expected = HearthWidgetSnapshot.sample(at: Date(timeIntervalSince1970: 100))
        try store.write(expected)
        XCTAssertEqual(store.read(), expected)
        expected.climate?.target = 22.5
        expected.connection = "Offline"
        try store.write(expected)
        XCTAssertEqual(store.read(), expected)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: store.folder.path), ["snapshot.json"])
    }

    func testSnapshotContainsOnlyDisplaySchema() throws {
        let data = try JSONEncoder().encode(HearthWidgetSnapshot.sample())
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["schemaVersion", "updatedAt", "connection", "climate", "activity", "energy", "deviceCount", "roomCount"])
        let climate = try XCTUnwrap(object["climate"] as? [String: Any])
        XCTAssertEqual(Set(climate.keys), ["entityID", "name", "mode", "target", "room", "available"])
        let activity = try XCTUnwrap(object["activity"] as? [String: Any])
        XCTAssertEqual(Set(activity.keys), ["title", "symbol", "date"])
        let encoded = String(decoding: data, as: UTF8.self)
        for forbidden in ["accessToken", "refreshToken", "ha.url", "attributes", "imageFile", "cameraID", "username"] {
            XCTAssertFalse(encoded.contains(forbidden), forbidden)
        }
    }

    func testMissingCorruptFutureAndOversizedSnapshotsAreRejected() throws {
        let store = try storage()
        XCTAssertNil(store.read())
        try Data("not JSON".utf8).write(to: store.file)
        XCTAssertNil(store.read())
        var future = HearthWidgetSnapshot.sample()
        future.schemaVersion = 999
        try store.write(future)
        XCTAssertNil(store.read())
        try Data(repeating: 0x20, count: 65_537).write(to: store.file)
        XCTAssertNil(store.read())
    }

    func testOversizedWriteDoesNotReplaceGoodSnapshot() throws {
        let store = try storage()
        let good = HearthWidgetSnapshot.sample()
        try store.write(good)
        var large = good
        large.activity?.title = String(repeating: "x", count: 66_000)
        XCTAssertThrowsError(try store.write(large))
        XCTAssertEqual(store.read(), good)
    }

    func testSnapshotPermissionsArePrivate() throws {
        let store = try storage()
        try store.write(.sample())
        let attrs = try FileManager.default.attributesOfItem(atPath: store.file.path)
        XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testTimelineTransitionsToStaleWhenTheAppStops() {
        let now = Date(timeIntervalSince1970: 1000)
        let snapshot = HearthWidgetSnapshot.sample(at: now)
        XCTAssertFalse(HearthWidgetTimeline.stale(snapshot, at: now.addingTimeInterval(299)))
        XCTAssertTrue(HearthWidgetTimeline.stale(snapshot, at: now.addingTimeInterval(300)))
        XCTAssertEqual(HearthWidgetTimeline.dates(snapshot, now: now), [now, now.addingTimeInterval(300)])
        XCTAssertEqual(HearthWidgetTimeline.refresh(after: now), now.addingTimeInterval(900))
    }

    func testTimelineDatesStayOrderedForOldSnapshots() {
        let now = Date(timeIntervalSince1970: 1000)
        let snapshot = HearthWidgetSnapshot.sample(at: now.addingTimeInterval(-3600))
        XCTAssertTrue(HearthWidgetTimeline.stale(snapshot, at: now))
        XCTAssertEqual(HearthWidgetTimeline.dates(snapshot, now: now), [now, now.addingTimeInterval(1)])
    }

    func testEverySupportedPageRoundTrips() {
        for page in ["rooms", "activity", "energy", "speakers", "devices", "security", "map"] {
            XCTAssertEqual(HearthWidgetLink.destination(HearthWidgetLink.url(page: page)), page)
        }
        XCTAssertEqual(HearthWidgetLink.destination(HearthWidgetLink.url(page: "unsupported")), "rooms")
    }

    func testClimateDeepLinkRoundTripsAndInvalidIDsFallback() {
        XCTAssertEqual(HearthWidgetLink.destination(HearthWidgetLink.climateURL(entityID: "climate.workspace_2")), "climate.workspace_2")
        for invalid in [nil, "", "climate.", "camera.workspace", "climate.workspace/turn_on", "climate.UPPER", "climate.a&service=turn_on"] as [String?] {
            XCTAssertEqual(HearthWidgetLink.destination(HearthWidgetLink.climateURL(entityID: invalid)), "rooms")
        }
    }

    func testUntrustedDeepLinksAreRejected() {
        for raw in [
            "https://widget/rooms", "hearth://other/rooms", "hearth://widget/unknown",
            "hearth://user:password@widget/rooms", "hearth://widget:8000/rooms",
            "hearth://widget/rooms#fragment", "hearth://widget/rooms?service=turn_on",
            "hearth://widget/climate", "hearth://widget/climate?entity=camera.test",
            "hearth://widget/climate?entity=climate.a&entity=climate.b",
            "hearth://widget/climate?entity=climate.a&service=turn_on",
            "hearth://widget/climate?entity=climate.a%2Fservice",
            "hearth://widget//rooms", "hearth://widget/rooms/"
        ] {
            XCTAssertNil(HearthWidgetLink.destination(URL(string: raw)!), raw)
        }
    }

    func testResizeKeepsTopLeftAndUsesOriginalTranslation() {
        let start = CGRect(x: 40, y: 400, width: 664, height: 170)
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let result = WidgetWindowGeometry.frame(start: start, translation: CGSize(width: -200, height: 10), resizing: true,
                                               minimum: CGSize(width: 360, height: 170), overview: true, screen: screen)
        XCTAssertEqual(result.minX, start.minX)
        XCTAssertEqual(result.maxY, start.maxY)
        XCTAssertEqual(result.width, 464)
        XCTAssertEqual(result.height, 280)
        XCTAssertEqual(WidgetWindowGeometry.frame(start: start, translation: CGSize(width: -200, height: 10), resizing: true,
            minimum: CGSize(width: 360, height: 170), overview: true, screen: screen), result)
    }

    func testNativeResizeAndRestoredNarrowOverviewUseAdaptiveMinimum() {
        XCTAssertEqual(WidgetWindowGeometry.constrainedSize(CGSize(width: 360, height: 170), minimum: CGSize(width: 360, height: 170), overview: true), CGSize(width: 360, height: 280))
        XCTAssertEqual(WidgetWindowGeometry.constrainedSize(CGSize(width: 620, height: 170), minimum: CGSize(width: 360, height: 170), overview: true), CGSize(width: 620, height: 170))
        XCTAssertEqual(WidgetWindowGeometry.constrainedSize(CGSize(width: 200, height: 100), minimum: CGSize(width: 280, height: 170), overview: false), CGSize(width: 280, height: 170))
    }

    func testResizeMaximumAndScreenBounds() {
        let result = WidgetWindowGeometry.frame(start: CGRect(x: 100, y: 200, width: 344, height: 170),
            translation: CGSize(width: 9000, height: 9000), resizing: true,
            minimum: CGSize(width: 280, height: 170), overview: false,
            screen: CGRect(x: 0, y: 0, width: 1000, height: 800))
        XCTAssertEqual(result.width, 900)
        XCTAssertEqual(result.height, 370)
        XCTAssertEqual(result.maxY, 370)
        XCTAssertEqual(result.minY, 0)
    }

    func testMoveDoesNotResizeOrAccumulateAndPreservesCrossDisplayMovement() {
        let start = CGRect(x: 40, y: 400, width: 344, height: 170)
        let result = WidgetWindowGeometry.frame(start: start, translation: CGSize(width: 1500, height: 35), resizing: false,
            minimum: CGSize(width: 280, height: 170), overview: false, screen: CGRect(x: 0, y: 0, width: 1000, height: 800))
        XCTAssertEqual(result, CGRect(x: 1540, y: 365, width: 344, height: 170))
    }
}
