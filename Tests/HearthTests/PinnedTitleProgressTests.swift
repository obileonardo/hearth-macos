import XCTest
@testable import Hearth

final class PinnedTitleProgressTests: XCTestCase {
    @MainActor
    func testOriginalHeadingRemainsTheOnlyVisibleHeadingUntilItLeaves() {
        XCTAssertEqual(PinnedTitleBar.progress(headerBottom: nil), 0)
        XCTAssertEqual(PinnedTitleBar.progress(headerBottom: 30), 0)
        XCTAssertEqual(PinnedTitleBar.progress(headerBottom: 0), 0)
    }
    @MainActor
    func testFloatingPillAppearsOverAShortScrollDistance() {
        XCTAssertEqual(PinnedTitleBar.progress(headerBottom: -9), 0.5)
        XCTAssertEqual(PinnedTitleBar.progress(headerBottom: -18), 1)
        XCTAssertEqual(PinnedTitleBar.progress(headerBottom: -100), 1)
    }
    @MainActor
    func testInvalidGeometryDoesNotShowAnUnpositionedPill() {
        XCTAssertEqual(PinnedTitleBar.progress(headerBottom: .nan), 0)
        XCTAssertEqual(PinnedTitleBar.progress(headerBottom: .infinity), 0)
    }
}
