import XCTest
@testable import Hearth

@MainActor
final class HASessionTests: XCTestCase {
    private let home = URL(string: "https://home.example")!
    private let other = URL(string: "https://other.example")!
    private let tokens: JSON = ["refresh_token": "fixture-refresh", "access_token": "fixture-access", "expires_in": 1800]

    private final class Memory {
        var saved: HASavedSession?
        var legacy: String?
        var failSave = false
        var failClear = false
        var saves = 0
        enum Failure: Error { case denied }
        var vault: HATokenSession.Vault {
            .init(load: { self.saved }, legacy: { self.legacy }, save: {
                if self.failSave { throw Failure.denied }
                self.saved = $0; self.saves += 1
            }, clear: {
                if self.failClear { throw Failure.denied }
                self.saved = nil; self.legacy = nil
            })
        }
    }

    func testCanonicalOriginsNormalizeDefaultsAndSeparateSchemeAndPort() {
        XCTAssertEqual(HASessionOrigin.canonical(URL(string: "https://HOME.example:443/path")!), "https://home.example")
        XCTAssertNotEqual(HASessionOrigin.canonical(home), HASessionOrigin.canonical(URL(string: "http://home.example")!))
        XCTAssertNotEqual(HASessionOrigin.canonical(home), HASessionOrigin.canonical(URL(string: "https://home.example:8123")!))
        for input in ["file:///tmp/value", "https://user:pass@home.example", "https://home.example?token=fixture", "https://home.example#fragment"] {
            XCTAssertNil(HASessionOrigin.canonical(URL(string: input)!))
        }
    }
    func testMismatchedSavedSessionNeverReachesRefreshTransport() async throws {
        let memory = Memory(); let session = HATokenSession(vault: memory.vault)
        try session.commit(tokens, at: home)
        do {
            _ = try await session.token(at: other, developmentToken: nil) { _ in XCTFail("No transport"); return self.tokens }
            XCTFail("Expected mismatch")
        } catch { XCTAssertEqual(error as? HASessionError, .originMismatch) }
    }
    func testSameOriginCacheRetainsValidAccessWithoutRefreshing() async throws {
        let session = HATokenSession(vault: Memory().vault)
        try session.commit(tokens, at: home)
        let result = try await session.token(at: URL(string: "https://HOME.example:443")!, developmentToken: nil) { _ in XCTFail("Cached"); return self.tokens }
        XCTAssertEqual(result, "fixture-access")
    }
    func testFailedCommitPreservesPreviousCredentialAndCache() async throws {
        let memory = Memory(); let session = HATokenSession(vault: memory.vault)
        try session.commit(tokens, at: home)
        let saved = memory.saved; let epoch = session.generation
        memory.failSave = true
        XCTAssertThrowsError(try session.commit(tokens, at: other))
        XCTAssertEqual(memory.saved, saved); XCTAssertEqual(session.generation, epoch)
        let value = try await session.token(at: home, developmentToken: nil) { _ in XCTFail("Cached"); return self.tokens }
        XCTAssertEqual(value, "fixture-access")
    }
    func testLegacyDoesNotSendBeforeLocalConfirmation() async {
        let memory = Memory(); memory.legacy = "fixture-legacy"
        let session = HATokenSession(vault: memory.vault)
        do {
            _ = try await session.token(at: home, developmentToken: nil) { _ in XCTFail("No transport"); return self.tokens }
            XCTFail("Confirmation required")
        } catch { XCTAssertEqual(error as? HASessionError, .confirmSavedServer) }
        XCTAssertEqual(memory.saves, 0)
    }
    func testLegacyConfirmationCannotBindAnEditedOrDevelopmentAddress() {
        let memory = Memory(); memory.legacy = "fixture-legacy"
        let session = HATokenSession(vault: memory.vault)
        XCTAssertThrowsError(try session.confirmLegacy(at: other, savedAtStartup: home))
        XCTAssertThrowsError(try session.confirmLegacy(at: home, savedAtStartup: nil))
        XCTAssertNil(memory.saved); XCTAssertEqual(memory.saves, 0)
    }
    func testConfirmedLegacyRetainsOriginalAndRefreshesOnlyBoundOrigin() async throws {
        let memory = Memory(); memory.legacy = "fixture-legacy"
        let session = HATokenSession(vault: memory.vault)
        try session.confirmLegacy(at: home, savedAtStartup: home)
        XCTAssertEqual(memory.legacy, "fixture-legacy")
        XCTAssertEqual(memory.saved?.origin, "https://home.example")
        let result = try await session.token(at: home, developmentToken: nil) { saved in
            XCTAssertEqual(saved.refreshToken, "fixture-legacy")
            XCTAssertEqual(saved.clientID, "https://home.example/")
            return self.tokens
        }
        XCTAssertEqual(result, "fixture-access")
    }
    func testFailedLegacySaveLeavesCredentialAndGenerationUnchanged() {
        let memory = Memory(); memory.legacy = "fixture-legacy"; memory.failSave = true
        let session = HATokenSession(vault: memory.vault)
        XCTAssertThrowsError(try session.confirmLegacy(at: home, savedAtStartup: home))
        XCTAssertNil(memory.saved); XCTAssertEqual(memory.legacy, "fixture-legacy"); XCTAssertEqual(session.generation, 0)
    }
    func testSignOutInvalidatesEvenWhenStorageCleanupFails() async throws {
        let memory = Memory(); let session = HATokenSession(vault: memory.vault)
        try session.commit(tokens, at: home); let epoch = session.generation
        memory.failClear = true
        XCTAssertThrowsError(try session.signOut())
        XCTAssertTrue(session.blocked); XCTAssertGreaterThan(session.generation, epoch)
        do {
            _ = try await session.token(at: home, developmentToken: "fixture-explicit") { _ in XCTFail("No refresh"); return self.tokens }
            XCTFail("Signed out")
        } catch { XCTAssertEqual(error as? HASessionError, .signedOut) }
    }
    func testInFlightRefreshCannotRestoreSignedOutSession() async throws {
        let memory = Memory(); memory.saved = HASavedSession(origin: "https://home.example", clientID: "https://home.example/", refreshToken: "fixture-refresh")
        let session = HATokenSession(vault: memory.vault)
        do {
            _ = try await session.token(at: home, developmentToken: nil) { _ in
                try session.signOut()
                return self.tokens
            }
            XCTFail("Stale response")
        } catch { XCTAssertEqual(error as? HASessionError, .staleSession) }
    }
    func testChangedEndpointDuringRefreshCannotPublishItsToken() async throws {
        let memory = Memory(); memory.saved = HASavedSession(origin: "https://home.example", clientID: "https://home.example/", refreshToken: "fixture-refresh")
        let session = HATokenSession(vault: memory.vault); var current = true
        do {
            _ = try await session.token(at: home, developmentToken: nil, stillCurrent: { current }) { _ in current = false; return self.tokens }
            XCTFail("Stale endpoint")
        } catch { XCTAssertEqual(error as? HASessionError, .staleSession) }
    }
    func testDevelopmentTokenDoesNotBindOrLoadLegacyCredential() async throws {
        let memory = Memory(); memory.legacy = "fixture-legacy"
        let session = HATokenSession(vault: memory.vault)
        let result = try await session.token(at: other, developmentToken: "fixture-explicit") { _ in XCTFail("No refresh"); return self.tokens }
        XCTAssertEqual(result, "fixture-explicit"); XCTAssertNil(memory.saved); XCTAssertEqual(memory.saves, 0)
    }
    func testAuthRedirectsNeverCarryBodiesAcrossOrigins() {
        XCTAssertTrue(HAAuthenticationRedirects.allowed(URL(string: "https://HOME.example:443/auth/token")!, from: home))
        for url in [other, URL(string: "http://home.example/auth/token")!, URL(string: "https://home.example:8123/auth/token")!, URL(string: "https://user:pass@home.example/auth/token")!] {
            XCTAssertFalse(HAAuthenticationRedirects.allowed(url, from: home))
        }
    }
    func testStoredClientIDCannotNameAnotherOrigin() {
        XCTAssertFalse(HASessionOrigin.permits(HASavedSession(origin: "https://home.example", clientID: "https://other.example/", refreshToken: "fixture-refresh"), at: home))
    }

    func testUppercaseSecureSchemeKeepsTheSameBoundOrigin() {
        let uppercase = URL(string: "HTTPS://HOME.example:443/path")!
        XCTAssertEqual(HASessionOrigin.canonical(uppercase), "https://home.example")
        let saved = HASavedSession(origin: "https://home.example", clientID: "https://home.example/", refreshToken: "fixture-refresh")
        XCTAssertTrue(HASessionOrigin.permits(saved, at: uppercase))
        XCTAssertTrue(HAWebSocketAuthentication.matches(URL(string: "WSS://HOME.example:443/api/websocket")!, expected: uppercase))
    }

    func testAlreadyCancelledTokenLookupDoesNotReadStorageOrRefresh() async {
        let session = HATokenSession(vault: .init(load: {
            XCTFail("Cancelled lookup must not read storage"); return nil
        }, legacy: { XCTFail("Cancelled lookup must not read legacy storage"); return nil },
           save: { _ in XCTFail("No save") }, clear: { XCTFail("No clear") }))
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await session.token(at: self.home, developmentToken: "fixture-explicit") { _ in
                XCTFail("Cancelled lookup must not refresh"); return self.tokens
            }
        }
        do { _ = try await task.value; XCTFail("Cancellation must propagate") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(session.generation, 0)
    }

    func testCancelledRefreshResponseIsNotCached() async throws {
        let memory = Memory()
        memory.saved = HASavedSession(origin: "https://home.example", clientID: "https://home.example/", refreshToken: "fixture-refresh")
        let session = HATokenSession(vault: memory.vault)
        var refreshes = 0
        let task = Task { @MainActor in
            try await session.token(at: self.home, developmentToken: nil) { _ in
                refreshes += 1
                // The transport returns after cancellation; the response must not become authority.
                withUnsafeCurrentTask { $0?.cancel() }
                return self.tokens
            }
        }
        do { _ = try await task.value; XCTFail("Cancellation must propagate") }
        catch { XCTAssertTrue(error is CancellationError) }
        let result = try await session.token(at: home, developmentToken: nil) { _ in
            refreshes += 1
            return ["access_token": "fixture-fresh-access", "expires_in": 1800]
        }
        XCTAssertEqual(refreshes, 2)
        XCTAssertEqual(result, "fixture-fresh-access")
        XCTAssertEqual(memory.saves, 0)
    }
}
