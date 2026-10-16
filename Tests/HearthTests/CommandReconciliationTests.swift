import Foundation
import XCTest
@testable import Hearth

@MainActor
final class CommandReconciliationTests: XCTestCase {
    func testRejectedNonClimateControlReadsOnlyItsExplicitTargetWithoutRetry() async {
        let action = DeviceCommand(domain: "camera", service: "turn_off", entityID: "camera.fixture")
        var sends = 0, reads: [String] = []
        do {
            try await CommandReconciliation.perform(action, send: { _ in
                sends += 1; throw ProviderError("Fixture rejection")
            }, refresh: { reads.append($0); return nil })
            XCTFail("Failure must reach the caller")
        } catch { XCTAssertEqual(error.localizedDescription, "Fixture rejection") }
        XCTAssertEqual(sends, 1)
        XCTAssertEqual(reads, ["camera.fixture"])
    }

    func testAcceptedControlDoesNotReadOrChangeState() async throws {
        try await CommandReconciliation.perform(DeviceCommand(domain: "switch", service: "turn_on", entityID: "switch.fixture"),
                                                send: { _ in }, refresh: { _ in XCTFail("No failure"); return nil })
    }

    func testBroadAndMissingTargetsNeverTriggerReadback() async {
        for id in [nil, "", "all", "camera.one,camera.two", "camera.one camera.two"] as [String?] {
            do {
                try await CommandReconciliation.perform(DeviceCommand(domain: "camera", service: "turn_off", entityID: id),
                                                        send: { _ in throw ProviderError("Rejected") },
                                                        refresh: { _ in XCTFail("No exact entity"); return nil })
            } catch { }
        }
    }

    func testDelayedSnapshotCannotReplaceNewerPushDuringFailureReadback() async {
        let id = "light.fixture"
        var displayed = Entity(id: id, state: "on", attributes: [:], lastUpdated: Date(timeIntervalSince1970: 10))
        do {
            try await CommandReconciliation.perform(DeviceCommand(domain: "light", service: "turn_on", entityID: id),
                                                    send: { _ in throw ProviderError("Rejected") }, refresh: { target in
                XCTAssertEqual(target, id)
                // A push arrives while get_states is pending.
                displayed = Entity(id: id, state: "off", attributes: [:], lastUpdated: Date(timeIntervalSince1970: 30))
                let delayed = Entity(id: id, state: "on", attributes: [:], lastUpdated: Date(timeIntervalSince1970: 20))
                if delayed.isAtLeastAsRecent(as: displayed) { displayed = delayed }
                return displayed
            })
        } catch { }
        XCTAssertEqual(displayed.state, "off")
        XCTAssertEqual(displayed.lastUpdated, Date(timeIntervalSince1970: 30))
    }

    func testEqualTimestampCanReplaceOptimisticStateWithReportedState() {
        let optimistic = Entity(id: "switch.fixture", state: "on", attributes: [:], lastUpdated: Date(timeIntervalSince1970: 10))
        let reported = Entity(id: optimistic.id, state: "off", attributes: [:], lastUpdated: optimistic.lastUpdated)
        XCTAssertTrue(reported.isAtLeastAsRecent(as: optimistic))
    }
}
