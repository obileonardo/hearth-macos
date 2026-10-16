import XCTest
@testable import Hearth

@MainActor
final class CommandSessionTests: XCTestCase {
    func testQueuedCommandRejectsChangedSignInBeforeWaiting() async {
        let session = CommandSession(generation: 1)
        do {
            try await session.waitForConnection(current: { 2 }, connected: { XCTFail("No new-session socket lookup"); return true },
                                                pause: { XCTFail("No wait") })
            XCTFail("An obsolete session cannot gain new authority")
        } catch { XCTAssertEqual(error as? HASessionError, .staleSession) }
    }

    func testSessionChangeWhileWaitingRejectsBeforeUsingNewSocket() async {
        let session = CommandSession(generation: 1)
        var generation = 1, ready = false, pauses = 0
        do {
            try await session.waitForConnection(current: { generation }, connected: { ready }, pause: {
                pauses += 1
                generation = 2
                ready = true
            })
            XCTFail("New server availability cannot authorize an old request")
        } catch { XCTAssertEqual(error as? HASessionError, .staleSession) }
        XCTAssertEqual(pauses, 1)
    }

    func testOrdinaryReconnectWithinSameSignInRemainsAllowed() async throws {
        let session = CommandSession(generation: 1)
        var ready = false, pauses = 0
        try await session.waitForConnection(current: { 1 }, connected: { ready }, pause: {
            pauses += 1
            ready = true
        })
        try session.check(current: 1) // The deferred transport rechecks the same authority.
        XCTAssertEqual(pauses, 1)
    }

    func testDeferredSendRejectsChangeAfterConnectionBecomesReady() async throws {
        let session = CommandSession(generation: 1)
        try await session.waitForConnection(current: { 1 }, connected: { true }, pause: { XCTFail("Already connected") })
        XCTAssertThrowsError(try session.check(current: 2)) { error in
            XCTAssertEqual(error as? HASessionError, .staleSession)
        }
    }

    func testCancelledConnectionWaitNeverChecksOrUsesTransport() async {
        let session = CommandSession(generation: 1)
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            try await session.waitForConnection(current: { 1 }, connected: { XCTFail("No transport"); return true },
                                                pause: { XCTFail("No wait") })
        }
        do { try await task.value; XCTFail("Cancellation must stop an unsent request") }
        catch { XCTAssertTrue(error is CancellationError) }
    }

    func testCancellationDuringWaitStopsEvenIfPauseReturnsNormally() async {
        let session = CommandSession(generation: 1)
        var pauses = 0
        let task = Task { @MainActor in
            try await session.waitForConnection(current: { 1 }, connected: { false }, pause: {
                pauses += 1
                withUnsafeCurrentTask { $0?.cancel() }
            })
        }
        do { try await task.value; XCTFail("Cancellation must propagate") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(pauses, 1)
    }

    func testCallCapturesSessionBeforeItsDeferredTaskAndDoesNotCommandAnotherSession() async throws {
        let domain = "HearthTests.CommandSession." + UUID().uuidString
        let preferences = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { preferences.removePersistentDomain(forName: domain) }
        let auth = HATokenSession(vault: .init(load: { nil }, legacy: { nil }, save: { _ in }, clear: {}))
        let store = HomeStore(defaults: preferences, environment: [:], authentication: auth, authenticationConnection: {})
        var sends = 0
        store.playDemo(devices: [], entities: [], deviceOf: [:], simulator: { _ in sends += 1; return nil })
        let finished = expectation(description: "Old-session action rejected")
        store.call(DeviceCommand(domain: "switch", service: "turn_on", entityID: "switch.fixture")) { result in
            if case .failure(let error) = result { XCTAssertEqual(error as? HASessionError, .staleSession) }
            else { XCTFail("An obsolete action cannot succeed") }
            finished.fulfill()
        }
        // Same MainActor turn: call's deferred task cannot start before sign-out.
        store.signOut()
        await fulfillment(of: [finished], timeout: 2)
        XCTAssertEqual(sends, 0)
        XCTAssertEqual(store.inFlight, 0)
        XCTAssertNil(store.actionError)
    }

    func testStaleReadbackDoesNotConsultTheNewSessionsDemoStore() async throws {
        let domain = "HearthTests.ReadbackSession." + UUID().uuidString
        let preferences = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { preferences.removePersistentDomain(forName: domain) }
        let auth = HATokenSession(vault: .init(load: { nil }, legacy: { nil }, save: { _ in }, clear: {}))
        let store = HomeStore(defaults: preferences, environment: [:], authentication: auth, authenticationConnection: {})
        let entity = Entity(id: "switch.fixture", state: "on", attributes: [:])
        store.playDemo(devices: [], entities: [entity], deviceOf: [:], simulator: { _ in XCTFail("No transport"); return nil })
        let oldEpoch = store.authenticationGeneration
        store.signOut()
        let result = await store.refreshEntity(entity.id, authenticationEpoch: oldEpoch)
        XCTAssertNil(result)
        XCTAssertEqual(store.entities[entity.id]?.state, "on")
    }
}
