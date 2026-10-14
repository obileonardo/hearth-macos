import XCTest
@testable import Hearth

final class MapCursorPolicyTests: XCTestCase {
    private var canvas: MapCursorPolicy.Context {
        .init(active: true, visible: true, keyWindow: true, sameWindow: true, insideVisibleRect: true, canvasHit: true)
    }

    func testHouseAndPinOwnOpenHandButBlankCanvasOwnsArrow() {
        XCTAssertEqual(MapCursorPolicy.choice(canvas, dragging: false, hitHouseOrPin: true), .openHand)
        XCTAssertEqual(MapCursorPolicy.choice(canvas, dragging: false, hitHouseOrPin: false), .arrow)
    }

    func testOverlappingTextFieldOrToolbarKeepsNativeCursor() {
        var state = canvas
        state.canvasHit = false
        XCTAssertEqual(MapCursorPolicy.choice(state, dragging: false, hitHouseOrPin: true), .inherited)
        XCTAssertEqual(MapCursorPolicy.choice(state, dragging: false, hitHouseOrPin: false), .inherited)
    }

    func testHiddenInactiveOrDepartingMapCannotWriteCursor() {
        for key in [\MapCursorPolicy.Context.active, \MapCursorPolicy.Context.visible,
                    \MapCursorPolicy.Context.keyWindow, \MapCursorPolicy.Context.sameWindow,
                    \MapCursorPolicy.Context.insideVisibleRect] {
            var state = canvas
            state[keyPath: key] = false
            XCTAssertFalse(state.ownsPoint)
            XCTAssertEqual(MapCursorPolicy.choice(state, dragging: false, hitHouseOrPin: true), .inherited)
            XCTAssertEqual(MapCursorPolicy.choice(state, dragging: false, hitHouseOrPin: false), .inherited)
        }
    }

    func testHoverCannotReplaceTheOwnedDragCursor() {
        XCTAssertEqual(MapCursorPolicy.choice(canvas, dragging: true, hitHouseOrPin: true), .inherited)
        XCTAssertEqual(MapCursorPolicy.choice(canvas, dragging: true, hitHouseOrPin: false), .inherited)
    }

    func testMouseUpCancellationAndDetachReleaseOnlyAnAcquiredCursor() {
        var lease = MapDragCursorLease()
        XCTAssertFalse(lease.end())
        XCTAssertTrue(lease.begin())
        XCTAssertFalse(lease.begin())
        XCTAssertTrue(lease.end())
        XCTAssertFalse(lease.end())
        XCTAssertFalse(lease.held)
    }

    func testRepeatedMapDragsHaveExactlyOnePopPerAcquisition() {
        var lease = MapDragCursorLease()
        var pushes = 0
        var pops = 0
        for _ in 0..<100 {
            if lease.begin() { pushes += 1 }
            if lease.begin() { pushes += 1 }
            if lease.end() { pops += 1 }
            if lease.end() { pops += 1 }
        }
        XCTAssertEqual(pushes, 100)
        XCTAssertEqual(pushes, pops)
        XCTAssertFalse(lease.held)
    }
}
