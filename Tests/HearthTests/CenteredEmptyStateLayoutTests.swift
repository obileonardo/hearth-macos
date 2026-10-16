import XCTest
@testable import Hearth

final class CenteredEmptyStateLayoutTests: XCTestCase {
    func testRemainingViewportStartsBelowControlsAndEndsAtDock() {
        XCTAssertEqual(CenteredEmptyStateLayout.minimumHeight(viewportHeight: 700, contentTop: 180,
                                                              dockObstruction: 70), 450)
        // An empty-state center is halfway between the controls and the dock's top.
        let height = CenteredEmptyStateLayout.minimumHeight(viewportHeight: 700, contentTop: 180,
                                                            dockObstruction: 70)!
        XCTAssertEqual(180 + height / 2, (180 + 700 - 70) / 2)
    }

    func testNarrowRemainingSpaceNeverProducesNegativeOrFixedContentHeight() {
        XCTAssertEqual(CenteredEmptyStateLayout.minimumHeight(viewportHeight: 240, contentTop: 190,
                                                              dockObstruction: 70), 0)
        XCTAssertEqual(CenteredEmptyStateLayout.minimumHeight(viewportHeight: 1, contentTop: 0,
                                                              dockObstruction: 0), 1)
    }

    func testStandaloneAndSnapshotViewsKeepTheirNaturalHeight() {
        XCTAssertNil(CenteredEmptyStateLayout.minimumHeight(viewportHeight: nil, contentTop: 120, dockObstruction: 70))
        XCTAssertNil(CenteredEmptyStateLayout.minimumHeight(viewportHeight: 700, contentTop: nil, dockObstruction: 70))
    }

    func testInvalidGeometryCannotExpandOrPoisonTheLayout() {
        for value: CGFloat in [.nan, .infinity, -.infinity, -1] {
            XCTAssertNil(CenteredEmptyStateLayout.minimumHeight(viewportHeight: value, contentTop: 120, dockObstruction: 70))
            XCTAssertNil(CenteredEmptyStateLayout.minimumHeight(viewportHeight: 700, contentTop: value, dockObstruction: 70))
            XCTAssertNil(CenteredEmptyStateLayout.minimumHeight(viewportHeight: 700, contentTop: 120, dockObstruction: value))
        }
        XCTAssertNil(CenteredEmptyStateLayout.minimumHeight(viewportHeight: 0, contentTop: 0, dockObstruction: 0))
    }

    func testLargerViewportsRecenterWithoutDependingOnScrollPosition() {
        XCTAssertEqual(CenteredEmptyStateLayout.minimumHeight(viewportHeight: 900, contentTop: 180,
                                                              dockObstruction: 70), 650)
        // Taller filters reduce the available room; there is no scroll-offset input.
        XCTAssertEqual(CenteredEmptyStateLayout.minimumHeight(viewportHeight: 900, contentTop: 240,
                                                              dockObstruction: 70), 590)
    }
}
