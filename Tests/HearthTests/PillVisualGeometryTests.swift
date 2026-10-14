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

}
