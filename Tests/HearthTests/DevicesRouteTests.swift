import XCTest
@testable import Hearth

final class DevicesRouteTests: XCTestCase {
    @MainActor
    func testDepartingHomeRetainsDemoAfterLiveRouteIsCleared() {
        var liveDemo: DemoEngine? = DemoEngine(.energy)
        let departing = DevicesRoute(home: .demo, section: nil, demo: liveDemo)
        weak var original = liveDemo
        liveDemo = nil
        let grid = DevicesRoute(home: nil, section: nil, demo: liveDemo)

        XCTAssertNotNil(original)
        XCTAssertTrue(departing.demo === original)
        XCTAssertTrue(departing.isDemo)
        XCTAssertFalse(grid.isDemo)
        XCTAssertNotEqual(departing, grid)
    }

    @MainActor
    func testSameEnginePreservesRouteIdentity() {
        let engine = DemoEngine(.energy)
        let first = DevicesRoute(home: .demo, section: nil, demo: engine)
        let next = DevicesRoute(home: .demo, section: nil, demo: engine)
        XCTAssertEqual(first, next)
    }

    @MainActor
    func testReplacementDemoHasDistinctRouteIdentity() {
        let first = DevicesRoute(home: .demo, section: nil, demo: DemoEngine(.energy))
        let next = DevicesRoute(home: .demo, section: nil, demo: DemoEngine(.energy))
        XCTAssertNotEqual(first, next)
    }

    @MainActor
    func testSectionDemoAndLivePageRemainDistinct() {
        let demo = DevicesRoute(home: nil, section: .energy, demo: DemoEngine(.energy))
        let live = DevicesRoute(home: nil, section: .energy, demo: nil)
        XCTAssertTrue(demo.isDemo)
        XCTAssertFalse(live.isDemo)
        XCTAssertNotEqual(demo, live)
        XCTAssertEqual(live, DevicesRoute(home: nil, section: .energy, demo: nil))
    }
}
