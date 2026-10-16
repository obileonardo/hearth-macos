import XCTest
@testable import Hearth

final class PanelTooltipPlacementTests: XCTestCase {
    private let viewport = CGSize(width: 448, height: 696)
    private let bubble = CGSize(width: 280, height: 116)

    func testLeftCameraCentersItsHelpAboveOrBelowTheIcon() throws {
        let anchor = CGRect(x: 174, y: 320, width: 26, height: 26)
        let frame = try XCTUnwrap(PanelTooltipPlacement.frame(anchor: anchor, viewport: viewport, bubble: bubble))
        XCTAssertEqual(frame.midX, anchor.midX)
        XCTAssertEqual(frame.minY, anchor.maxY + 8)
    }

    func testRightCameraShiftsHelpInwardToTheRightMargin() throws {
        let anchor = CGRect(x: 382, y: 320, width: 26, height: 26)
        let frame = try XCTUnwrap(PanelTooltipPlacement.frame(anchor: anchor, viewport: viewport, bubble: bubble))
        XCTAssertEqual(frame.maxX, viewport.width - 12)
        XCTAssertLessThan(frame.minX, anchor.minX)
    }

    func testFarLeftAndRightAnchorsStayInsideViewport() throws {
        for x in [-30.0, 0, 12, 174, 382, 436, 470] {
            let frame = try XCTUnwrap(PanelTooltipPlacement.frame(anchor: CGRect(x: x, y: 300, width: 26, height: 26), viewport: viewport, bubble: bubble))
            XCTAssertGreaterThanOrEqual(frame.minX, 12)
            XCTAssertLessThanOrEqual(frame.maxX, viewport.width - 12)
        }
    }

    func testLowerCameraFlipsHelpAboveTheControl() throws {
        let anchor = CGRect(x: 382, y: 610, width: 26, height: 26)
        let frame = try XCTUnwrap(PanelTooltipPlacement.frame(anchor: anchor, viewport: viewport, bubble: bubble))
        XCTAssertEqual(frame.maxY, anchor.minY - 8)
    }

    func testTopAndBottomAndOversizedMessagesClampToAvailableArea() throws {
        for size in [CGSize(width: 448, height: 696), CGSize(width: 280, height: 200), CGSize(width: 100, height: 80)] {
            for y in [-200.0, 0, 30, 150, 650, 900] {
                let frame = try XCTUnwrap(PanelTooltipPlacement.frame(anchor: CGRect(x: 400, y: y, width: 26, height: 26), viewport: size, bubble: CGSize(width: 800, height: 1200)))
                XCTAssertGreaterThanOrEqual(frame.minX, 12)
                XCTAssertGreaterThanOrEqual(frame.minY, 12)
                XCTAssertLessThanOrEqual(frame.maxX, size.width - 12)
                XCTAssertLessThanOrEqual(frame.maxY, size.height - 12)
            }
        }
    }

    func testInvalidAndNonfiniteGeometryIsRejected() {
        for size in [CGSize.zero, CGSize(width: -1, height: 10), CGSize(width: CGFloat.infinity, height: 10), CGSize(width: CGFloat.nan, height: 10)] {
            XCTAssertNil(PanelTooltipPlacement.frame(anchor: .zero, viewport: size, bubble: bubble))
        }
        XCTAssertNil(PanelTooltipPlacement.frame(anchor: CGRect(x: CGFloat.nan, y: 10, width: 20, height: 20), viewport: viewport, bubble: bubble))
        XCTAssertNil(PanelTooltipPlacement.frame(anchor: .zero, viewport: viewport, bubble: .zero))
        XCTAssertNil(PanelTooltipPlacement.frame(anchor: .zero, viewport: viewport, bubble: bubble, margin: -1))
    }
}
