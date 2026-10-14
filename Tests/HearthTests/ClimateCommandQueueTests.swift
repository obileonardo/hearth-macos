import Foundation
import XCTest
@testable import Hearth

@MainActor
final class ClimateCommandQueueTests: XCTestCase {
    private enum FixtureFailure: Error { case rejected }

    @MainActor private final class Gate {
        private var opened = false
        private var waiters: [CheckedContinuation<Void, Never>] = []
        func wait() async {
            if opened { return }
            await withCheckedContinuation { waiters.append($0) }
        }
        func open() {
            opened = true
            let current = waiters
            waiters.removeAll()
            current.forEach { $0.resume() }
        }
    }

    func testSameDeviceCommandsKeepRequestedOrder() async throws {
        let queue = ClimateCommandQueue(spacing: .zero)
        let started = Gate(), release = Gate()
        var order: [Int] = []
        var submitted: [Int] = []
        let first = Task {
            submitted.append(1)
            return try await queue.run(key: "fixture-ac") {
                order.append(1); started.open(); await release.wait(); return 1
            }
        }
        await started.wait()
        let second = Task {
            submitted.append(2)
            return try await queue.run(key: "fixture-ac") { order.append(2); return 2 }
        }
        let third = Task {
            submitted.append(3)
            return try await queue.run(key: "fixture-ac") { order.append(3); return 3 }
        }
        release.open()
        let values = try await [first.value, second.value, third.value]
        XCTAssertEqual(values, [1, 2, 3])
        // Compare actual submissions on MainActor, not Task creation/yield order.
        XCTAssertEqual(order, submitted)
    }

    func testSameDeviceOperationsNeverOverlap() async throws {
        let queue = ClimateCommandQueue(spacing: .zero)
        var active = 0, maximum = 0
        let jobs = (0..<4).map { _ in Task {
            try await queue.run(key: "fixture-ac") {
                active += 1; maximum = max(maximum, active)
                defer { active -= 1 }
                try await Task.sleep(for: .milliseconds(10))
            }
        } }
        for job in jobs { try await job.value }
        XCTAssertEqual(maximum, 1)
        XCTAssertEqual(active, 0)
    }

    func testErrorStillAllowsNextCommandToRun() async throws {
        let queue = ClimateCommandQueue(spacing: .zero)
        let started = Gate(), release = Gate()
        var order: [String] = []
        let failed = Task {
            try await queue.run(key: "fixture-ac") {
                order.append("failed"); started.open(); await release.wait()
                throw FixtureFailure.rejected
            }
        }
        await started.wait()
        let next = Task { try await queue.run(key: "fixture-ac") { order.append("next"); return 2 } }
        release.open()
        do { try await failed.value; XCTFail("Fixture failure must propagate") }
        catch FixtureFailure.rejected {}
        catch { XCTFail("Unexpected error: \(error)") }
        let value = try await next.value
        XCTAssertEqual(value, 2)
        XCTAssertEqual(order, ["failed", "next"])
    }

    func testCancellationSkipsUnsentCommandWithoutBreakingChain() async throws {
        let queue = ClimateCommandQueue(spacing: .zero)
        let started = Gate(), release = Gate()
        var order: [String] = []
        let first = Task { try await queue.run(key: "fixture-ac") {
            order.append("first"); started.open(); await release.wait()
        } }
        await started.wait()
        let cancelled = Task { try await queue.run(key: "fixture-ac") { order.append("cancelled") } }
        await Task.yield()
        cancelled.cancel()
        let next = Task { try await queue.run(key: "fixture-ac") { order.append("next") } }
        release.open()
        try await first.value
        do { try await cancelled.value; XCTFail("Unsent cancelled job must fail") }
        catch is CancellationError {}
        catch { XCTFail("Unexpected error: \(error)") }
        try await next.value
        XCTAssertEqual(order, ["first", "next"])
    }

    func testDifferentDeviceKeysRemainConcurrent() async throws {
        let queue = ClimateCommandQueue(spacing: .zero)
        let started = Gate(), release = Gate()
        let otherCompleted = expectation(description: "Other device is not blocked")
        let first = Task { try await queue.run(key: "fixture-one") {
            started.open(); await release.wait()
        } }
        await started.wait()
        let other = Task { try await queue.run(key: "fixture-two") { otherCompleted.fulfill() } }
        await fulfillment(of: [otherCompleted], timeout: 1)
        release.open()
        try await first.value
        try await other.value
    }

    func testCooldownStartsAfterPreviousOutcome() async throws {
        let queue = ClimateCommandQueue(spacing: .milliseconds(40))
        let clock = ContinuousClock()
        let finished = try await queue.run(key: "fixture-ac") { clock.now }
        let nextStart = try await queue.run(key: "fixture-ac") { clock.now }
        XCTAssertGreaterThanOrEqual(finished.duration(to: nextStart), .milliseconds(40))
    }

    func testCancellationAfterStartKeepsActualOutcome() async throws {
        let queue = ClimateCommandQueue(spacing: .zero)
        let started = Gate(), release = Gate()
        let running = Task { try await queue.run(key: "fixture-ac") {
            started.open(); await release.wait()
            try Task.checkCancellation()
            return 42
        } }
        await started.wait()
        running.cancel()
        release.open()
        let result = try await running.value
        XCTAssertEqual(result, 42)
    }

    func testScopeUsesOnlyExactClimateDeviceAndVerifiedSiblings() {
        let climate = Entity(id: "climate.fixture", state: "cool", attributes: [:])
        let switchEntity = Entity(id: "switch.fixture_display", state: "on", attributes: [:])
        let other = Entity(id: "switch.fixture_other", state: "off", attributes: [:])
        let entities = [climate.id: climate, switchEntity.id: switchEntity, other.id: other]
        let registry = [
            climate.id: RegistryEntry(deviceID: "fixture-ac", hidden: false),
            switchEntity.id: RegistryEntry(deviceID: "fixture-ac", hidden: false),
            other.id: RegistryEntry(deviceID: "fixture-light", hidden: false),
        ]
        func body(_ domain: String, _ target: Any) -> JSON {
            ["type": "call_service", "domain": domain, "target": ["entity_id": target]]
        }
        XCTAssertEqual(ClimateCommandScope.key(for: body("climate", climate.id), registry: registry, entities: entities), "device:fixture-ac")
        XCTAssertEqual(ClimateCommandScope.key(for: body("climate", [climate.id]), registry: registry, entities: entities), "device:fixture-ac")
        XCTAssertEqual(ClimateCommandScope.key(for: body("switch", switchEntity.id), registry: registry, entities: entities), "device:fixture-ac")
        XCTAssertNil(ClimateCommandScope.key(for: body("switch", other.id), registry: registry, entities: entities))
        XCTAssertNil(ClimateCommandScope.key(for: body("climate", [climate.id, "climate.fixture_second"]), registry: registry, entities: entities))
        XCTAssertNil(ClimateCommandScope.key(for: body("media_player", "media_player.fixture"), registry: registry, entities: entities))
        XCTAssertNil(ClimateCommandScope.key(for: ["type": "get_states"], registry: registry, entities: entities))
        var broad = body("climate", climate.id)
        broad["target"] = ["entity_id": climate.id, "area_id": "fixture-area"]
        XCTAssertNil(ClimateCommandScope.key(for: broad, registry: registry, entities: entities))
        XCTAssertEqual(ClimateCommandScope.key(for: body("climate", "climate.unregistered"), registry: [:], entities: [:]), "entity:climate.unregistered")
    }

    func testFreshnessParsesAttributeTimestampAndRejectsUndatedOrOlderSnapshot() throws {
        let parsed = try XCTUnwrap(Entity([
            "entity_id": "climate.fixture", "state": "cool", "attributes": [:],
            "last_changed": "2026-10-14T09:00:00Z", "last_updated": "2026-10-14T09:00:01.500Z",
        ]))
        XCTAssertEqual(parsed.lastUpdated?.timeIntervalSince(parsed.lastChanged!), 1.5)
        let old = Entity(id: parsed.id, state: "auto", attributes: [:], lastChanged: Date(timeIntervalSince1970: 300), lastUpdated: Date(timeIntervalSince1970: 100))
        let current = Entity(id: parsed.id, state: "cool", attributes: [:], lastChanged: Date(timeIntervalSince1970: 90), lastUpdated: Date(timeIntervalSince1970: 101))
        XCTAssertFalse(old.isAtLeastAsRecent(as: current))
        XCTAssertTrue(current.isAtLeastAsRecent(as: old))
        XCTAssertTrue(current.isAtLeastAsRecent(as: current))
        let undated = Entity(id: parsed.id, state: "dry", attributes: [:])
        XCTAssertFalse(undated.isAtLeastAsRecent(as: current))
        XCTAssertFalse(undated.isAtLeastAsRecent(as: undated))
        let legacy = Entity(id: parsed.id, state: "cool", attributes: [:], lastChanged: Date(timeIntervalSince1970: 102))
        XCTAssertTrue(legacy.isAtLeastAsRecent(as: current))
    }

    func testDemoRefreshAndCommandRemainInMemoryWithoutInventingState() async throws {
        let store = HomeStore()
        let entity = Entity(id: "climate.fixture", state: "cool", attributes: ["temperature": 22])
        var calls = 0
        store.playDemo(devices: [], entities: [entity], deviceOf: [:]) { _ in calls += 1; return nil }
        let refreshed = await store.refreshEntity(entity.id)
        XCTAssertEqual(refreshed?.state, "cool")
        XCTAssertEqual(calls, 0)
        let result = try await store.command(["type": "call_service", "domain": "climate", "service": "set_hvac_mode", "target": ["entity_id": entity.id], "service_data": ["hvac_mode": "dry"]])
        XCTAssertNil(result)
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(store.entities[entity.id]?.state, "cool")
    }
}
