import AppKit
import Foundation
import CoreGraphics
import XCTest
@testable import Hearth

final class PillVisualGeometryTests: XCTestCase {
    func testRequestedCapsuleAddsFourPointsWhenMenuBarHasRoom() {
        let metrics = StatusPillGeometry(availableHeight: 28)
        XCTAssertEqual(metrics.bodyHeight, 20 + 4)
        XCTAssertEqual(metrics.canvasHeight, 26)
    }

    func testSmallerMenuBarsNeverClipAnOversizedPill() {
        for height: CGFloat in [18, 20, 22, 24, 25, 26, 30, 38] {
            let metrics = StatusPillGeometry(availableHeight: height)
            XCTAssertLessThanOrEqual(metrics.bodyHeight, metrics.canvasHeight)
            XCTAssertLessThanOrEqual(metrics.canvasHeight, height)
            XCTAssertLessThanOrEqual(metrics.bodyHeight, 24)
        }
        XCTAssertEqual(StatusPillGeometry(availableHeight: 22).bodyHeight, 22)
        XCTAssertEqual(StatusPillGeometry(availableHeight: 24).bodyHeight, 24)
    }

    func testFractionalBarHeightRoundsDownForCrispRendering() {
        let metrics = StatusPillGeometry(availableHeight: 23.75)
        XCTAssertEqual(metrics.canvasHeight, 23)
        XCTAssertEqual(metrics.bodyHeight, 23)
    }

    func testInvalidMenuBarHeightUsesFiniteFallback() {
        for value: CGFloat in [0, -1, .nan, .infinity, -.infinity] {
            let metrics = StatusPillGeometry(availableHeight: value)
            XCTAssertEqual(metrics.canvasHeight, 22)
            XCTAssertEqual(metrics.bodyHeight, 22)
        }
    }

    func testBothFlashEndpointsKeepNominalShadowAndBadgeInsidePanel() {
        for shown in [false, true] {
            let top = FlashPillGeometry.offset(shown: shown, reduceMotion: false) + FlashPillGeometry.topPadding
            XCTAssertGreaterThanOrEqual(top + FlashPillGeometry.shadowOffset - FlashPillGeometry.shadowRadius, 0)
            XCTAssertLessThanOrEqual(top + FlashPillGeometry.bodyHeight + FlashPillGeometry.shadowOffset + FlashPillGeometry.shadowRadius,
                                     FlashPillGeometry.panelHeight)
            XCTAssertGreaterThanOrEqual(top - 4, 0) // Dismiss badge overhang.
        }
    }

    func testReduceMotionUsesOnePositionAndNormalDropIsSmall() {
        XCTAssertEqual(FlashPillGeometry.offset(shown: false, reduceMotion: true), FlashPillGeometry.offset(shown: true, reduceMotion: true))
        XCTAssertEqual(FlashPillGeometry.visibleOffset - FlashPillGeometry.hiddenOffset, 6)
    }
    func testHoverRegionContainsCapsuleAndFullDismissHitbox() {
        let body = FlashPillGeometry.bodyRect(bodyWidth: 376)
        let bounds = CGRect(x: 0, y: 0, width: FlashPillGeometry.interactionWidth(bodyWidth: 376), height: FlashPillGeometry.interactionHeight)
        XCTAssertTrue(bounds.contains(body))
        XCTAssertTrue(bounds.contains(FlashPillGeometry.dismissRect))
        XCTAssertEqual(body.size, CGSize(width: 376, height: 68))
        XCTAssertEqual(bounds.size, CGSize(width: 380, height: 72))
    }

    func testHoverPaddingPreservesVisibleCapsulePlacement() {
        let originalCenter: CGFloat = 456 / 2
        let expandedWidth = FlashPillGeometry.interactionWidth(bodyWidth: 376)
        let body = FlashPillGeometry.bodyRect(bodyWidth: 376)
        let actualCenter = (456 - expandedWidth) / 2 - FlashPillGeometry.dismissOverhang / 2 + body.midX
        XCTAssertEqual(actualCenter, originalCenter)
        let bodyTop = FlashPillGeometry.visibleOffset - FlashPillGeometry.dismissOverhang + body.minY + FlashPillGeometry.topPadding
        XCTAssertEqual(bodyTop, FlashPillGeometry.visibleOffset + FlashPillGeometry.topPadding)
    }


    func testFullBlurTailsFitDuringBothAnimationEndpoints() {
        let bodyWidth: CGFloat = 376
        let panelWidth: CGFloat = 456
        let horizontalPadding = (panelWidth - bodyWidth) / 2
        XCTAssertGreaterThanOrEqual(horizontalPadding, FlashPillGeometry.shadowBleed)
        for shown in [false, true] {
            for reduceMotion in [false, true] {
                let top = FlashPillGeometry.offset(shown: shown, reduceMotion: reduceMotion) + FlashPillGeometry.topPadding
                XCTAssertGreaterThanOrEqual(top + FlashPillGeometry.shadowOffset - FlashPillGeometry.shadowBleed, 0)
                XCTAssertLessThanOrEqual(top + FlashPillGeometry.bodyHeight + FlashPillGeometry.shadowOffset + FlashPillGeometry.shadowBleed,
                                         FlashPillGeometry.panelHeight)
            }
        }
    }

    func testFlashFollowsChangedLiveStatusCenterWithoutChangingMainPanelAnchor() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 878)
        let first = CGRect(x: 620, y: 878, width: 160, height: 22)
        let changed = CGRect(x: 520, y: 878, width: 260, height: 22)
        var session = MenuPanelAnchorSession()
        let fixedAnchor = session.resolve(liveAnchor: first, screenFrame: screen)
        let fixedPanel = MenuPanelGeometry.frame(anchor: fixedAnchor, visibleFrame: visible, panelSize: CGSize(width: 448, height: 696))
        let firstFlash = FlashPillGeometry.frame(anchor: first, visibleFrame: visible, screenFrame: screen, panelWidth: 456)
        let nextFlash = FlashPillGeometry.frame(anchor: changed, visibleFrame: visible, screenFrame: screen, panelWidth: 456)
        XCTAssertEqual(firstFlash.midX, first.midX)
        XCTAssertEqual(nextFlash.midX, changed.midX)
        XCTAssertEqual(nextFlash.midX - firstFlash.midX, -50)
        XCTAssertEqual(nextFlash.size, firstFlash.size)
        XCTAssertEqual(MenuPanelGeometry.frame(anchor: session.resolve(liveAnchor: changed, screenFrame: screen),
                                               visibleFrame: visible, panelSize: fixedPanel.size), fixedPanel)
    }

    func testClearShadowCanvasKeepsVisibleBodyGapConstant() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        for barHeight: CGFloat in [22, 24, 28, 38] {
            let anchor = CGRect(x: 600, y: screen.maxY - barHeight, width: 180, height: barHeight)
            let visible = CGRect(x: 0, y: 0, width: 1440, height: anchor.minY)
            let frame = FlashPillGeometry.frame(anchor: anchor, visibleFrame: visible, screenFrame: screen, panelWidth: 456)
            let lift = FlashPillGeometry.bodyLift(anchor: anchor, screenFrame: screen)
            let bodyTop = frame.maxY - FlashPillGeometry.visibleBodyTop + lift
            XCTAssertEqual(anchor.minY - bodyTop, FlashPillGeometry.bodyGap)
            XCTAssertEqual(lift, barHeight < 24 ? 24 - barHeight : 0)
            XCTAssertLessThanOrEqual(frame.maxY, screen.maxY)
        }
    }

    func testFlashClampsScreenEdgesAndSupportsNegativeDisplayCoordinates() {
        let screen = CGRect(x: -1920, y: 300, width: 1920, height: 1080)
        let visible = CGRect(x: -1920, y: 330, width: 1920, height: 1026)
        for x: CGFloat in [-1920, -80] {
            let anchor = CGRect(x: x, y: 1356, width: 80, height: 24)
            let frame = FlashPillGeometry.frame(anchor: anchor, visibleFrame: visible, screenFrame: screen, panelWidth: 456)
            XCTAssertGreaterThanOrEqual(frame.minX, visible.minX + 8)
            XCTAssertLessThanOrEqual(frame.maxX, visible.maxX - 8)
            XCTAssertGreaterThanOrEqual(frame.minY, visible.minY + 8)
            XCTAssertLessThanOrEqual(frame.maxY, screen.maxY)
        }
    }
    func testNotificationCapsuleSitsTwelvePointsBelowTheStatusCapsule() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let anchor = CGRect(x: 600, y: 876, width: 180, height: 24)
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 876)
        let frame = FlashPillGeometry.frame(anchor: anchor, visibleFrame: visible,
                                           screenFrame: screen, panelWidth: 456)
        let visibleCapsuleTop = frame.maxY - FlashPillGeometry.visibleBodyTop
        XCTAssertEqual(anchor.minY - visibleCapsuleTop, 12)
        XCTAssertEqual(frame.midX, anchor.midX)
    }

    /// The geometry alone passed while AppKit pushed the shown window below the
    /// menu bar, adding a full menu bar to the gap. Check the real window.
    func testShownFlashPanelKeepsItsMenuBarOverlap() throws {
        guard let screen = NSScreen.main, screen.frame.maxY - screen.visibleFrame.maxY >= 20 else {
            throw XCTSkip("Needs a display with a menu bar")
        }
        let anchor = CGRect(x: screen.frame.midX - 90, y: screen.frame.maxY - 26, width: 180, height: 18)
        let frame = FlashPillGeometry.frame(anchor: anchor, visibleFrame: screen.visibleFrame,
                                           screenFrame: screen.frame, panelWidth: 456)
        XCTAssertGreaterThan(frame.maxY, screen.visibleFrame.maxY)

        let panel = FlashPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                               backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.isFloatingPanel = true
        panel.ignoresMouseEvents = true
        defer { panel.orderOut(nil) }
        panel.setFrame(frame, display: false)
        panel.orderFrontRegardless()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        XCTAssertEqual(panel.frame, frame)
        XCTAssertEqual(anchor.minY - (panel.frame.maxY - FlashPillGeometry.visibleBodyTop), 12)

        let moved = frame.offsetBy(dx: 0, dy: 1)
        panel.setFrame(moved, display: false)
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        XCTAssertEqual(panel.frame, moved)
    }

    func testConstrainedDisplayKeepsNotificationInsideScreenBeforePreservingGap() {
        let screen = CGRect(x: -800, y: 100, width: 800, height: 180)
        let visible = CGRect(x: -800, y: 100, width: 800, height: 156)
        let anchor = CGRect(x: -440, y: 256, width: 180, height: 24)
        let frame = FlashPillGeometry.frame(anchor: anchor, visibleFrame: visible,
                                           screenFrame: screen, panelWidth: 456)
        XCTAssertGreaterThanOrEqual(frame.minY, visible.minY + 8)
        XCTAssertLessThanOrEqual(frame.maxY, screen.maxY)
        let gap = anchor.minY - (frame.maxY - FlashPillGeometry.visibleBodyTop)
        XCTAssertGreaterThanOrEqual(gap, 0)
        XCTAssertLessThanOrEqual(gap, 12)
    }

    func testStatusCapsuleExcludesTheCanvasMargin() {
        let tall = CGRect(x: 600, y: 874, width: 120, height: 26)
        XCTAssertEqual(StatusPillGeometry.capsule(in: tall), CGRect(x: 600, y: 875, width: 120, height: 24))
        let exact = CGRect(x: 600, y: 876, width: 120, height: 24)
        XCTAssertEqual(StatusPillGeometry.capsule(in: exact), exact)
        let short = CGRect(x: 600, y: 880, width: 120, height: 20)
        XCTAssertEqual(StatusPillGeometry.capsule(in: short), short)
    }

}
