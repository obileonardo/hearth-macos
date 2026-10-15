import Foundation
import XCTest
@testable import Hearth

@MainActor
final class ActivityPreviewIsolationTests: XCTestCase {
    private func seed(title: String = "Person at the demo entrance") -> ActivityLog.Item {
        ActivityLog.Item(kind: .person, title: title, place: "Demo entrance",
                         date: Date(timeIntervalSince1970: 1_700_000_000),
                         entityID: "binary_sensor.demo_entrance_person", cameraID: "camera.demo_entrance")
    }

    func testExplicitEmptyPreviewDoesNotLoadPersistentHistory() {
        let log = ActivityLog(previewItems: [])
        XCTAssertTrue(log.items.isEmpty)
        XCTAssertEqual(log.unread, 0)
    }

    func testPreviewKeepsOnlySuppliedEventsAndStripsExternalReferences() {
        var item = seed()
        item.imageFile = "/synthetic-fixture/event.jpg"
        item.faceSample = UUID()
        item.plainTitle = "Unrendered fixture title"
        let log = ActivityLog(previewItems: [item])
        XCTAssertEqual(log.items.count, 1)
        XCTAssertEqual(log.items.first?.id, item.id)
        XCTAssertEqual(log.items.first?.title, item.title)
        XCTAssertEqual(log.items.first?.date, item.date)
        XCTAssertNil(log.items.first?.cameraID)
        XCTAssertNil(log.items.first?.imageFile)
        XCTAssertNil(log.items.first?.faceSample)
        XCTAssertNil(log.items.first?.plainTitle)
    }

    func testReadAndClearRemainLocalAndLeaveSentinelFilesUnchanged() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("HearthActivityPreviewTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let historyURL = folder.appendingPathComponent("activity.json")
        let imageURL = folder.appendingPathComponent("fixture-image.jpg")
        let diskItems = try JSONEncoder().encode([seed(title: "Disk-only fixture")])
        let imageBytes = Data("Synthetic image sentinel; not a photograph".utf8)
        try diskItems.write(to: historyURL)
        try imageBytes.write(to: imageURL)
        var item = seed()
        item.imageFile = imageURL.path
        let first = ActivityLog(previewItems: [item])
        let separate = ActivityLog(previewItems: [item])
        first.markAllRead()
        XCTAssertEqual(first.unread, 0)
        XCTAssertEqual(separate.unread, 1)
        first.clear()
        XCTAssertTrue(first.items.isEmpty)
        XCTAssertEqual(separate.items.count, 1)
        XCTAssertEqual(try Data(contentsOf: historyURL), diskItems)
        XCTAssertEqual(try Data(contentsOf: imageURL), imageBytes)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted(), ["activity.json", "fixture-image.jpg"])
    }

    func testPreviewNotificationChoicesStayWithinEachInstance() {
        let first = ActivityLog(previewItems: [])
        let separate = ActivityLog(previewItems: [])
        for kind in ActivityLog.Kind.allCases {
            XCTAssertEqual(first.notifies(kind), kind.notifiesByDefault)
            first.setNotifies(kind, !kind.notifiesByDefault)
            XCTAssertEqual(first.notifies(kind), !kind.notifiesByDefault)
            XCTAssertEqual(separate.notifies(kind), kind.notifiesByDefault)
        }
    }

    func testLiveAttachmentEventsBackfillAndFaceWorkDoNotChangePreview() async {
        let item = seed()
        let log = ActivityLog(previewItems: [item])
        let store = HomeStore() // No connection is started.
        log.attach(store)
        let old = Entity(id: "binary_sensor.demo_motion", state: "off", attributes: ["device_class": "motion"])
        let new = Entity(id: old.id, state: "on", attributes: old.attributes)
        log.handle(new, old)
        await log.backfill()
        await log.learnFaces()
        log.refreshFaceTitles()
        XCTAssertEqual(log.items.count, 1)
        XCTAssertEqual(log.items.first?.id, item.id)
        XCTAssertEqual(log.items.first?.title, item.title)
        XCTAssertNil(log.items.first?.cameraID)
        XCTAssertEqual(log.unread, 1)
    }
}
