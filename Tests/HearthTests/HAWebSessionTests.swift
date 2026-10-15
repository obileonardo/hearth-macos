import XCTest
import WebKit
@testable import Hearth

@MainActor
final class HAWebSessionTests: XCTestCase {
    func testInvalidationReplacesEphemeralViewAndRemovesOldScripts() {
        let web = HAWebModel()
        let original = web.view
        original.configuration.userContentController.addUserScript(WKUserScript(source: "void 0", injectionTime: .atDocumentStart, forMainFrameOnly: true))
        XCTAssertFalse(original.configuration.websiteDataStore.isPersistent)
        web.invalidate()
        XCTAssertFalse(web.view === original)
        XCTAssertTrue(original.configuration.userContentController.userScripts.isEmpty)
        XCTAssertTrue(web.view.configuration.userContentController.userScripts.isEmpty)
        XCTAssertFalse(web.view.configuration.websiteDataStore.isPersistent)
        XCTAssertFalse(web.canGoBack); XCTAssertFalse(web.canGoForward)
    }
    func testDelayedAuthenticationCannotReinstallInvalidatedWebSession() async throws {
        let domain = "HearthTests.WebSession." + UUID().uuidString
        let preferences = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { preferences.removePersistentDomain(forName: domain) }
        preferences.set("https://home.example", forKey: "ha.url")
        let credential = HASavedSession(origin: "https://home.example", clientID: "https://home.example/", refreshToken: "fixture-refresh")
        let auth = HATokenSession(vault: .init(load: { credential }, legacy: { nil }, save: { _ in }, clear: {}))
        let web = HAWebModel()
        let store = HomeStore(defaults: preferences, environment: [:], authentication: auth, authenticationTransport: { request in
            web.invalidate()
            return (try JSONSerialization.data(withJSONObject: ["access_token": "fixture-access", "expires_in": 1800]),
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }, authenticationConnection: {})
        await web.load(store)
        XCTAssertTrue(web.view.configuration.userContentController.userScripts.isEmpty)
        XCTAssertFalse(web.loading)
    }
    func testSignOutInvalidatesWebBeforeStorageCleanup() async throws {
        let domain = "HearthTests.WebSignOut." + UUID().uuidString
        let preferences = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { preferences.removePersistentDomain(forName: domain) }
        preferences.set("https://home.example", forKey: "ha.url")
        let web = HAWebModel()
        let initial = web.view
        let auth = HATokenSession(vault: .init(load: { nil }, legacy: { nil }, save: { _ in }, clear: {
            XCTAssertFalse(web.view === initial)
        }))
        let store = HomeStore(defaults: preferences, environment: [:], authentication: auth,
            authenticationTransport: { _ in XCTFail("No network"); throw HASessionError.signedOut }, authenticationConnection: {})
        await web.load(store) // Subscribes, but signed-out fixture cannot navigate or fetch.
        store.signOut()
        XCTAssertTrue(web.view.configuration.userContentController.userScripts.isEmpty)
        XCTAssertFalse(store.isSignedIn)
        XCTAssertTrue(preferences.bool(forKey: "ha.signedOut"))
    }
}
