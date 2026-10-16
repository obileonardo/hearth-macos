import XCTest
@testable import Hearth

final class PinnedTitleProgressTests: XCTestCase {
    @MainActor
    func testOriginalHeadingRemainsVisibleBeforeReachingTop() {
        XCTAssertEqual(PinnedTitleBar.progress(headerTop: nil), 0)
        XCTAssertEqual(PinnedTitleBar.progress(headerTop: 30), 0)
        XCTAssertEqual(PinnedTitleBar.progress(headerTop: 0), 0)
    }
    @MainActor
    func testFloatingCardAppearsBeforeOriginalTitleClips() {
        XCTAssertEqual(PinnedTitleBar.progress(headerTop: -9), 0.5)
        XCTAssertEqual(PinnedTitleBar.progress(headerTop: -18), 1)
        XCTAssertEqual(PinnedTitleBar.progress(headerTop: -100), 1)
    }
    @MainActor
    func testInvalidGeometryDoesNotShowAnUnpositionedCard() {
        XCTAssertEqual(PinnedTitleBar.progress(headerTop: .nan), 0)
        XCTAssertEqual(PinnedTitleBar.progress(headerTop: .infinity), 0)
    }
    @MainActor
    func testFloatingCardKeepsRequestedHeightAndPanelInsets() {
        XCTAssertEqual(PinnedTitleBar.height, 68)
        XCTAssertEqual(PinnedTitleBar.cornerRadius, 18)
        XCTAssertEqual(PinnedTitleBar.illustrationFrame, 35 * 0.75)
        XCTAssertEqual(PinnedTitleBar.illustrationSize, 26.25 * 0.75)
        XCTAssertEqual(PinnedTitleBar.edgeInset, 12)
    }
}
