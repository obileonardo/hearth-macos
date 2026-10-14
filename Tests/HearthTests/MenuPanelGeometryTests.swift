import Foundation
import XCTest
@testable import Hearth

final class MenuPanelGeometryTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)
    private let size = CGSize(width: 430, height: 640)

    func testCenteredBelowStatusItem() {
        let result = MenuPanelGeometry.frame(anchor: CGRect(x: 620, y: 880, width: 160, height: 24), visibleFrame: screen, panelSize: size)
        XCTAssertEqual(result.midX, 700)
        XCTAssertLessThanOrEqual(result.maxY, screen.maxY - 8)
    }
    func testTracksChangedStatusCenterWithoutChangingContentWidth() {
        let first = MenuPanelGeometry.frame(anchor: CGRect(x: 620, y: 880, width: 160, height: 24), visibleFrame: screen, panelSize: size)
        let second = MenuPanelGeometry.frame(anchor: CGRect(x: 520, y: 880, width: 260, height: 24), visibleFrame: screen, panelSize: size)
        XCTAssertEqual(first.width, second.width)
        XCTAssertEqual(second.midX - first.midX, -50)
    }
    func testBothEdgesStayOnScreen() {
        for x in [CGFloat(0), 1430] {
            let result = MenuPanelGeometry.frame(anchor: CGRect(x: x, y: 880, width: 100, height: 24), visibleFrame: screen, panelSize: size)
            XCTAssertGreaterThanOrEqual(result.minX, 8)
            XCTAssertLessThanOrEqual(result.maxX, screen.maxX - 8)
        }
    }
    func testExternalScreenCoordinatesRemainIndependent() {
        let external = CGRect(x: -1920, y: 300, width: 1920, height: 1080)
        let result = MenuPanelGeometry.frame(anchor: CGRect(x: -1040, y: 1385, width: 180, height: 24), visibleFrame: external, panelSize: size)
        XCTAssertEqual(result.midX, -950)
        XCTAssertGreaterThanOrEqual(result.minY, external.minY + 8)
    }
    func testSmallScreenBoundsThePanel() {
        let small = CGRect(x: 0, y: 0, width: 400, height: 500)
        let result = MenuPanelGeometry.frame(anchor: CGRect(x: 200, y: 500, width: 100, height: 24), visibleFrame: small, panelSize: size)
        XCTAssertEqual(result.width, 384)
        XCTAssertEqual(result.height, 484)
        XCTAssertTrue(small.contains(result))
    }
    @MainActor
    func testRequestedBreathingRoomRetainsScreenClamping() {
        XCTAssertEqual(Theme.panelSize.height, 648 + 48)
        XCTAssertEqual(PanelView.footerTopExtra, 32)
        XCTAssertEqual(PanelView.footerBottomExtra, 6)
        XCTAssertEqual(PanelView.footerHeight, 64 + 32 + 6)
        let small = CGRect(x: 0, y: 0, width: 1024, height: 650)
        let result = MenuPanelGeometry.frame(anchor: CGRect(x: 700, y: 650, width: 160, height: 24),
                                             visibleFrame: small, panelSize: Theme.panelSize)
        XCTAssertEqual(result.height, 634)
        XCTAssertTrue(small.contains(result))
    }

}
