import Combine
import XCTest
@testable import Hearth

@MainActor
final class HomeEnergyPresentationTests: XCTestCase {
    private func sensor(_ id: String, watts: Double) -> Entity {
        Entity(id: "sensor.\(id)_power", state: String(watts), attributes: ["device_class": "power", "unit_of_measurement": "W"])
    }

    private func store(_ readings: [(String, Double)]) -> HomeStore {
        let store = HomeStore()
        let entities = readings.map { sensor($0.0, watts: $0.1) }
        store.playDemo(devices: readings.map { DeviceInfo(id: $0.0, name: "Same device", manufacturer: "Fixture", model: "Power monitor") },
                       entities: entities, deviceOf: Dictionary(uniqueKeysWithValues: readings.map { ("sensor.\($0.0)_power", $0.0) }),
                       simulator: { _ in nil })
        return store
    }

    private func energy(_ store: HomeStore) -> HomeEnergy {
        // Missing fixture file: initialization reads no personal data and never saves.
        let list = HomeList(file: FileManager.default.temporaryDirectory.appendingPathComponent("hearth-energy-fixture-\(UUID().uuidString).json"))
        return HomeEnergy(home: list.main, store: store, list: list, gadgets: [], everything: true)
    }

    func testDemoSamplePublishesOnceWithEveryReadingFromTheSameMoment() {
        let store = store([("fixture_a", 100), ("fixture_b", 200), ("fixture_c", 300)])
        var samples: [[String: Entity]] = []
        let subscription = store.$entities.dropFirst().sink { samples.append($0) }
        store.playDemo(update: [sensor("fixture_a", watts: 400), sensor("fixture_b", watts: 500)])
        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(samples.first?["sensor.fixture_a_power"]?.state, "400.0")
        XCTAssertEqual(samples.first?["sensor.fixture_b_power"]?.state, "500.0")
        XCTAssertEqual(samples.first?["sensor.fixture_c_power"]?.state, "300.0")
        withExtendedLifetime(subscription) {}
    }

    func testEmptyAndNonDemoSamplesDoNotPublishOrWriteState() {
        let demo = store([("fixture_a", 100)])
        var demoPublications = 0
        let first = demo.$entities.dropFirst().sink { _ in demoPublications += 1 }
        demo.playDemo(update: [])
        XCTAssertEqual(demoPublications, 0)
        let live = HomeStore()
        var livePublications = 0
        let second = live.$entities.dropFirst().sink { _ in livePublications += 1 }
        live.playDemo(update: [sensor("fixture_a", watts: 100)])
        XCTAssertEqual(livePublications, 0)
        XCTAssertTrue(live.entities.isEmpty)
        withExtendedLifetime([first, second]) {}
    }

    func testAtomicMergeKeepsLastDuplicateAndAddsNewDemoEntity() {
        let store = store([("fixture_a", 100)])
        store.playDemo(update: [sensor("fixture_a", watts: 200), sensor("fixture_a", watts: 250), sensor("fixture_new", watts: 50)])
        XCTAssertEqual(store.entities["sensor.fixture_a_power"]?.state, "250.0")
        XCTAssertEqual(store.entities["sensor.fixture_new_power"]?.state, "50.0")
    }

    func testExactPowerAndNameTiesUseStableDeviceIdentity() {
        let first = energy(store([("fixture_c", 100), ("fixture_a", 100), ("fixture_b", 100)]))
        let second = energy(store([("fixture_b", 100), ("fixture_c", 100), ("fixture_a", 100)]))
        XCTAssertEqual(first.users.map(\.id), ["fixture_a", "fixture_b", "fixture_c"])
        XCTAssertEqual(second.users.map(\.id), first.users.map(\.id))
        XCTAssertEqual(first.devices.map(\.id), ["fixture_a", "fixture_b", "fixture_c"])
    }

    func testActualReadingCrossingChangesRankWithoutRoundingOrHysteresis() {
        let store = store([("fixture_a", 100.01), ("fixture_b", 100)])
        XCTAssertEqual(energy(store).users.map(\.id), ["fixture_a", "fixture_b"])
        store.playDemo(update: [sensor("fixture_a", watts: 100), sensor("fixture_b", watts: 100.01)])
        let changed = energy(store)
        XCTAssertEqual(changed.users.map(\.id), ["fixture_b", "fixture_a"])
        XCTAssertEqual(changed.users.first?.watts, 100.01)
        XCTAssertEqual(changed.devicesWatts ?? 0, 200.01, accuracy: 0.000001)
    }

    func testShareAndWidthRemainFiniteInsideTheTrack() {
        XCTAssertEqual(HomeEnergyPresentation.share(watts: 25, total: 100), 0.25)
        XCTAssertEqual(HomeEnergyPresentation.share(watts: 200, total: 100), 1)
        for invalid in [Double.nan, .infinity, -.infinity, -1, 0] {
            XCTAssertEqual(HomeEnergyPresentation.share(watts: invalid, total: 100), 0)
            XCTAssertEqual(HomeEnergyPresentation.share(watts: 100, total: invalid), 0)
        }
        for width in [0.0, 2, 4, 100, 404] {
            for fraction in [Double.nan, .infinity, -.infinity, -1, 0, 0.001, 0.5, 1, 2] {
                let bar = HomeEnergyPresentation.barWidth(available: width, fraction: fraction)
                XCTAssertTrue(bar.isFinite)
                XCTAssertTrue((0...width).contains(bar))
            }
        }
        XCTAssertEqual(HomeEnergyPresentation.barWidth(available: .nan, fraction: 1), 0)
        XCTAssertEqual(HomeEnergyPresentation.barWidth(available: -1, fraction: 1), 0)
        XCTAssertEqual(HomeEnergyPresentation.barWidth(available: 100, fraction: 0.001), 4)
    }

    func testLocalTweenFinishesBeforeDemoCadenceAnd600xIsPreserved() {
        XCTAssertGreaterThan(HomeEnergyPresentation.animationDuration, 0)
        XCTAssertLessThan(HomeEnergyPresentation.animationDuration, 0.5)
        XCTAssertEqual(DemoEngine.Speed.tenMinutes.rawValue, 600)
    }
}
