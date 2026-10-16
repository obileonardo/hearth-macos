import XCTest
@testable import Hearth

@MainActor
final class HASignInFlowTests: XCTestCase {
    private let home = URL(string: "https://home.example")!
    private let tokens: JSON = ["refresh_token": "fixture-refresh", "access_token": "fixture-access", "expires_in": 1800]

    private func defaults() throws -> (UserDefaults, String) {
        let name = "HearthTests.SignIn." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defaults.set(home.absoluteString, forKey: "ha.url")
        return (defaults, name)
    }
    private func response(_ request: URLRequest, _ object: JSON) throws -> (Data, URLResponse) {
        (try JSONSerialization.data(withJSONObject: object), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
    func testFailedSecondServerLoginPreservesSavedServerAndCurrentSession() async throws {
        let (preferences, domain) = try defaults(); defer { preferences.removePersistentDomain(forName: domain) }
        var saved: HASavedSession?
        let auth = HATokenSession(vault: .init(load: { saved }, legacy: { nil }, save: { saved = $0 }, clear: { saved = nil }))
        try auth.commit(tokens, at: home)
        let previous = saved
        var paths: [String] = []
        let store = HomeStore(defaults: preferences, environment: [:], authentication: auth, authenticationTransport: { request in
            XCTAssertEqual(request.url?.host, "other.example")
            paths.append(request.url!.path)
            if request.url!.path == "/auth/login_flow" { return try self.response(request, ["flow_id": "fixture-flow"]) }
            return try self.response(request, ["errors": ["base": "invalid_auth"]])
        }, authenticationConnection: { XCTFail("Failed login cannot reconnect") })
        do { try await store.signIn(url: "https://other.example", username: "fixture", password: "fixture"); XCTFail("Expected failure") } catch {}
        XCTAssertEqual(preferences.string(forKey: "ha.url"), home.absoluteString)
        XCTAssertEqual(saved, previous)
        XCTAssertEqual(paths, ["/auth/login_flow", "/auth/login_flow/fixture-flow"])
        let token = try await store.validAccessToken()
        XCTAssertEqual(token, "fixture-access")
    }
    func testSuccessfulLoginCommitsOnlyAfterSecureSave() async throws {
        let (preferences, domain) = try defaults(); defer { preferences.removePersistentDomain(forName: domain) }
        var saved: HASavedSession?
        let auth = HATokenSession(vault: .init(load: { saved }, legacy: { nil }, save: {
            XCTAssertEqual(preferences.string(forKey: "ha.url"), self.home.absoluteString)
            saved = $0
        }, clear: { saved = nil }))
        var reconnects = 0
        let store = HomeStore(defaults: preferences, environment: [:], authentication: auth, authenticationTransport: { request in
            switch request.url!.path {
            case "/auth/login_flow": return try self.response(request, ["flow_id": "fixture-flow"])
            case "/auth/login_flow/fixture-flow": return try self.response(request, ["type": "create_entry", "result": "fixture-code"])
            default: return try self.response(request, self.tokens)
            }
        }, authenticationConnection: { reconnects += 1 })
        try await store.signIn(url: "https://other.example", username: "fixture", password: "fixture")
        XCTAssertEqual(saved?.origin, "https://other.example")
        XCTAssertEqual(preferences.string(forKey: "ha.url"), "https://other.example")
        XCTAssertEqual(reconnects, 1)
    }
    func testDevelopmentURLCannotReuseBoundSavedToken() async throws {
        let (preferences, domain) = try defaults(); defer { preferences.removePersistentDomain(forName: domain) }
        var saved: HASavedSession?
        let auth = HATokenSession(vault: .init(load: { saved }, legacy: { nil }, save: { saved = $0 }, clear: { saved = nil }))
        try auth.commit(tokens, at: home)
        let store = HomeStore(defaults: preferences, environment: ["HA_URL": "https://other.example"], authentication: auth,
            authenticationTransport: { _ in XCTFail("No credential request"); throw HASessionError.originMismatch }, authenticationConnection: {})
        do { _ = try await store.validAccessToken(); XCTFail("Expected mismatch") }
        catch { XCTAssertEqual(error as? HASessionError, .originMismatch) }
    }

    @MainActor
    private final class Gate {
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

    func testAlreadyCancelledSignInDoesNotSendOrChangeSavedServer() async throws {
        let (preferences, domain) = try defaults()
        defer { preferences.removePersistentDomain(forName: domain) }
        let auth = HATokenSession(vault: .init(load: { nil }, legacy: { nil },
            save: { _ in XCTFail("No save") }, clear: { XCTFail("No clear") }))
        let store = HomeStore(defaults: preferences, environment: [:], authentication: auth,
            authenticationTransport: { _ in XCTFail("No transport"); throw HASessionError.signedOut },
            authenticationConnection: { XCTFail("No reconnect") })
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            try await store.signIn(url: "https://other.example", username: "fixture", password: "fixture")
        }
        do { try await task.value; XCTFail("Cancellation must propagate") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(preferences.string(forKey: "ha.url"), home.absoluteString)
        XCTAssertEqual(store.authenticationGeneration, 0)
    }

    func testCancelledSignInTokenResponsePreservesCurrentSession() async throws {
        let (preferences, domain) = try defaults()
        defer { preferences.removePersistentDomain(forName: domain) }
        var saved: HASavedSession?
        let auth = HATokenSession(vault: .init(load: { saved }, legacy: { nil }, save: { saved = $0 }, clear: { saved = nil }))
        try auth.commit(tokens, at: home)
        let previous = saved
        let store = HomeStore(defaults: preferences, environment: [:], authentication: auth, authenticationTransport: { request in
            switch request.url!.path {
            case "/auth/login_flow": return try self.response(request, ["flow_id": "fixture-flow"])
            case "/auth/login_flow/fixture-flow": return try self.response(request, ["type": "create_entry", "result": "fixture-code"])
            default:
                withUnsafeCurrentTask { $0?.cancel() }
                return try self.response(request, self.tokens)
            }
        }, authenticationConnection: { XCTFail("Cancelled login cannot reconnect") })
        let task = Task { @MainActor in
            try await store.signIn(url: "https://other.example", username: "fixture", password: "fixture")
        }
        do { try await task.value; XCTFail("Cancellation must propagate") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(saved, previous)
        XCTAssertEqual(preferences.string(forKey: "ha.url"), home.absoluteString)
        XCTAssertEqual(store.authenticationGeneration, 0)
        let access = try await store.validAccessToken()
        XCTAssertEqual(access, "fixture-access")
    }

    func testOlderSignInCannotCommitAfterTheNewerAttemptCompletes() async throws {
        let (preferences, domain) = try defaults()
        defer { preferences.removePersistentDomain(forName: domain) }
        var saved: HASavedSession?
        var saves = 0, reconnects = 0
        let auth = HATokenSession(vault: .init(load: { saved }, legacy: { nil }, save: {
            saved = $0; saves += 1
        }, clear: { saved = nil }))
        let olderReady = Gate(), releaseOlder = Gate()
        let store = HomeStore(defaults: preferences, environment: [:], authentication: auth, authenticationTransport: { request in
            switch request.url!.path {
            case "/auth/login_flow": return try self.response(request, ["flow_id": "fixture-flow"])
            case "/auth/login_flow/fixture-flow": return try self.response(request, ["type": "create_entry", "result": "fixture-code"])
            default:
                if request.url!.host == "older.example" {
                    olderReady.open()
                    await releaseOlder.wait()
                }
                return try self.response(request, self.tokens)
            }
        }, authenticationConnection: { reconnects += 1 })
        let older = Task { @MainActor in
            try await store.signIn(url: "https://older.example", username: "fixture", password: "fixture")
        }
        defer { releaseOlder.open(); older.cancel() }
        await olderReady.wait()
        do {
            try await store.signIn(url: "https://newer.example", username: "fixture", password: "fixture")
        } catch {
            releaseOlder.open()
            _ = await older.result
            throw error
        }
        releaseOlder.open()
        do { try await older.value; XCTFail("An older attempt cannot replace the newer sign-in") }
        catch { XCTAssertEqual(error as? HASessionError, .staleSession) }
        XCTAssertEqual(saved?.origin, "https://newer.example")
        XCTAssertEqual(preferences.string(forKey: "ha.url"), "https://newer.example")
        XCTAssertEqual(saves, 1)
        XCTAssertEqual(reconnects, 1)
        XCTAssertEqual(store.authenticationGeneration, 1)
    }
}
