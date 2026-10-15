import Foundation
import CoreGraphics
import XCTest
@testable import Hearth

final class MenuPanelAnchorSessionTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

    func testStatusTextWidthChangesKeepOpeningPanelFrame() {
        var session = MenuPanelAnchorSession()
        let opening = CGRect(x: 620, y: 880, width: 160, height: 24)
        let first = session.resolve(liveAnchor: opening, screenFrame: screen)
        let changed = session.resolve(liveAnchor: CGRect(x: 520, y: 880, width: 260, height: 24), screenFrame: screen)
        XCTAssertEqual(first, changed)
        let size = CGSize(width: 448, height: 696)
        XCTAssertEqual(MenuPanelGeometry.frame(anchor: first, visibleFrame: screen, panelSize: size),
                       MenuPanelGeometry.frame(anchor: changed, visibleFrame: screen, panelSize: size))
    }

    func testReopeningOrExplicitMoveCapturesNewAnchor() {
        var session = MenuPanelAnchorSession()
        _ = session.resolve(liveAnchor: CGRect(x: 620, y: 880, width: 160, height: 24), screenFrame: screen)
        session.reset()
        let moved = CGRect(x: 320, y: 880, width: 160, height: 24)
        XCTAssertEqual(session.resolve(liveAnchor: moved, screenFrame: screen), moved)
    }

    func testDisplayMoveReanchorsAndStillClamps() {
        var session = MenuPanelAnchorSession()
        _ = session.resolve(liveAnchor: CGRect(x: 620, y: 880, width: 160, height: 24), screenFrame: screen)
        let external = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let moved = CGRect(x: -180, y: 1080, width: 160, height: 24)
        let anchor = session.resolve(liveAnchor: moved, screenFrame: external)
        XCTAssertEqual(anchor, moved)
        let frame = MenuPanelGeometry.frame(anchor: anchor, visibleFrame: external, panelSize: CGSize(width: 448, height: 696))
        XCTAssertTrue(external.contains(frame))
        XCTAssertLessThanOrEqual(frame.maxX, external.maxX - 8)
    }

    func testDockOrMenuBoundsChangeClampsRetainedAnchor() {
        var session = MenuPanelAnchorSession()
        let opening = CGRect(x: 620, y: 880, width: 160, height: 24)
        _ = session.resolve(liveAnchor: opening, screenFrame: screen)
        let usable = CGRect(x: 0, y: 50, width: 1440, height: 600)
        let anchor = session.resolve(liveAnchor: CGRect(x: 500, y: 880, width: 280, height: 24), screenFrame: screen)
        let frame = MenuPanelGeometry.frame(anchor: anchor, visibleFrame: usable, panelSize: CGSize(width: 448, height: 696))
        XCTAssertTrue(usable.contains(frame))
        XCTAssertEqual(frame.midX, opening.midX)
    }

    func testOpenMenuSlotFitsCurrentStatusesAndCapsScreenUse() {
        XCTAssertEqual(MenuStatusSlotGeometry.width(imageWidths: [120, 180, 240], screenWidth: 1440), 240)
        XCTAssertEqual(MenuStatusSlotGeometry.width(imageWidths: [120, 900], screenWidth: 1440), 320)
        XCTAssertEqual(MenuStatusSlotGeometry.width(imageWidths: [120, 900], screenWidth: 600), 200)
        XCTAssertEqual(MenuStatusSlotGeometry.width(imageWidths: [.nan, .infinity], screenWidth: 1440), 1)
    }
}
