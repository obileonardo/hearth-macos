import AppKit
import XCTest
@testable import Hearth

final class RoomStripDragTests: XCTestCase {
    func testHorizontalStripRejectsTheTallVerticalParent() {
        XCTAssertTrue(RoomStripDragGeometry.isHorizontalStrip(document: CGSize(width: 1000, height: 180), viewport: CGSize(width: 300, height: 180)))
        XCTAssertFalse(RoomStripDragGeometry.isHorizontalStrip(document: CGSize(width: 1000, height: 1400), viewport: CGSize(width: 300, height: 600)))
        XCTAssertFalse(RoomStripDragGeometry.isHorizontalStrip(document: CGSize(width: 300, height: 180), viewport: CGSize(width: 300, height: 180)))
        XCTAssertFalse(RoomStripDragGeometry.isHorizontalStrip(document: CGSize(width: 1000, height: 180), viewport: .zero))
    }

    func testHorizontalIntentRejectsClicksVerticalAndDiagonalMotion() {
        XCTAssertFalse(RoomStripDragGeometry.isHorizontal(.zero))
        XCTAssertFalse(RoomStripDragGeometry.isHorizontal(CGPoint(x: 3, y: 0)))
        XCTAssertFalse(RoomStripDragGeometry.isHorizontal(CGPoint(x: 4, y: 20)))
        XCTAssertFalse(RoomStripDragGeometry.isHorizontal(CGPoint(x: 10, y: 10)))
        XCTAssertTrue(RoomStripDragGeometry.isHorizontal(CGPoint(x: 8, y: 1)))
        XCTAssertTrue(RoomStripDragGeometry.isHorizontal(CGPoint(x: -8, y: 1)))
        XCTAssertFalse(RoomStripDragGeometry.isHorizontal(CGPoint(x: CGFloat.nan, y: 0)))
        XCTAssertFalse(RoomStripDragGeometry.isHorizontal(CGPoint(x: 8, y: CGFloat.infinity)))
    }

    func testDraggingMovesContentWithTheMouseAndClampsBothEdges() {
        XCTAssertEqual(RoomStripDragGeometry.origin(start: 100, translation: 30, documentMinX: 0, documentWidth: 1000, viewportWidth: 300), 70)
        XCTAssertEqual(RoomStripDragGeometry.origin(start: 100, translation: -30, documentMinX: 0, documentWidth: 1000, viewportWidth: 300), 130)
        XCTAssertEqual(RoomStripDragGeometry.origin(start: 100, translation: 300, documentMinX: 0, documentWidth: 1000, viewportWidth: 300), 0)
        XCTAssertEqual(RoomStripDragGeometry.origin(start: 100, translation: -1000, documentMinX: 0, documentWidth: 1000, viewportWidth: 300), 700)
    }

    func testSmallDocumentsAndShiftedDocumentOriginsStayWithinBounds() {
        XCTAssertEqual(RoomStripDragGeometry.origin(start: 0, translation: -100, documentMinX: 0, documentWidth: 200, viewportWidth: 300), 0)
        XCTAssertEqual(RoomStripDragGeometry.origin(start: 10, translation: 100, documentMinX: 10, documentWidth: 500, viewportWidth: 300), 10)
        XCTAssertEqual(RoomStripDragGeometry.origin(start: 10, translation: -1000, documentMinX: 10, documentWidth: 500, viewportWidth: 300), 210)
    }

    func testMalformedOrOverflowedGeometryProducesNoScrollPoint() {
        XCTAssertNil(RoomStripDragGeometry.origin(start: .nan, translation: 10, documentMinX: 0, documentWidth: 500, viewportWidth: 300))
        XCTAssertNil(RoomStripDragGeometry.origin(start: 0, translation: .infinity, documentMinX: 0, documentWidth: 500, viewportWidth: 300))
        XCTAssertNil(RoomStripDragGeometry.origin(start: 0, translation: 10, documentMinX: 0, documentWidth: 500, viewportWidth: 0))
        XCTAssertNil(RoomStripDragGeometry.origin(start: 0, translation: 10, documentMinX: 0, documentWidth: -1, viewportWidth: 300))
        XCTAssertNil(RoomStripDragGeometry.origin(start: 0, translation: 10, documentMinX: .greatestFiniteMagnitude, documentWidth: .greatestFiniteMagnitude, viewportWidth: 300))
    }

    @MainActor
    private func strip() -> NSScrollView {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 180))
        scroll.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 1000, height: 180))
        return scroll
    }

    @MainActor
    func testSwiftUIGestureMovesTheNativeStripWithoutInstallingCompetingRecognizers() {
        let scroll = strip()
        let count = scroll.gestureRecognizers.count
        let coordinator = RoomStripDragCoordinator()
        coordinator.attach(to: scroll)
        coordinator.move(translation: CGSize(width: -80, height: 1))
        XCTAssertEqual(scroll.contentView.bounds.origin.x, 80)
        coordinator.move(translation: CGSize(width: -120, height: 2))
        XCTAssertEqual(scroll.contentView.bounds.origin.x, 120)
        XCTAssertEqual(scroll.gestureRecognizers.count, count)
        coordinator.end()
        coordinator.move(translation: CGSize(width: 30, height: 0))
        XCTAssertEqual(scroll.contentView.bounds.origin.x, 90)
    }

    @MainActor
    func testVerticalIntentIsNeverReinterpretedAsHorizontalDuringOneDrag() {
        let scroll = strip()
        let coordinator = RoomStripDragCoordinator()
        coordinator.attach(to: scroll)
        coordinator.move(translation: CGSize(width: 2, height: 20))
        coordinator.move(translation: CGSize(width: -100, height: 20))
        XCTAssertEqual(scroll.contentView.bounds.origin.x, 0)
        coordinator.end()
        coordinator.move(translation: CGSize(width: -50, height: 0))
        XCTAssertEqual(scroll.contentView.bounds.origin.x, 50)
    }

    @MainActor
    func testDetachedOrReparentedGestureCannotMoveThePreviousStrip() {
        let first = strip(), second = strip()
        let coordinator = RoomStripDragCoordinator()
        coordinator.attach(to: first)
        coordinator.move(translation: CGSize(width: -80, height: 0))
        XCTAssertEqual(first.contentView.bounds.origin.x, 80)
        coordinator.attach(to: second)
        coordinator.move(translation: CGSize(width: -40, height: 0))
        XCTAssertEqual(first.contentView.bounds.origin.x, 80)
        XCTAssertEqual(second.contentView.bounds.origin.x, 40)
        coordinator.attach(to: nil)
        coordinator.move(translation: CGSize(width: -100, height: 0))
        XCTAssertEqual(second.contentView.bounds.origin.x, 40)
        XCTAssertNil(coordinator.scrollView)
    }

    @MainActor
    func testProbeFindsInnerStripInsteadOfVerticalParentAndNeverStealsHitTesting() {
        let outer = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 700))
        let outerDocument = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 1400))
        outer.documentView = outerDocument
        let inner = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 180))
        outerDocument.addSubview(inner)
        let strip = NSView(frame: NSRect(x: 0, y: 0, width: 1000, height: 180))
        inner.documentView = strip
        let probe = RoomStripDragProbeView(drag: RoomStripDragCoordinator())
        strip.addSubview(probe)
        XCTAssertTrue(RoomStripDragProbeView.nearestScrollView(from: probe) === inner)
        XCTAssertNil(probe.hitTest(.zero))
        probe.retire()
    }
}
