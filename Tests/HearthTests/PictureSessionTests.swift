import XCTest
@testable import Hearth

@MainActor
final class PictureSessionTests: XCTestCase {
    private func preferences() throws -> (UserDefaults, String) {
        let domain = "HearthTests.PictureSession." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defaults.set("https://other.example", forKey: "ha.url")
        return (defaults, domain)
    }

    func testProxyImagesCannotUseAnotherServersSavedCredential() async throws {
        let (defaults, domain) = try preferences()
        defer { defaults.removePersistentDomain(forName: domain) }
        let saved = HASavedSession(origin: "https://home.example", clientID: "https://home.example/", refreshToken: "fixture-refresh")
        let auth = HATokenSession(vault: .init(load: { saved }, legacy: { nil }, save: { _ in XCTFail("No save") }, clear: {}))
        let store = HomeStore(defaults: defaults, environment: [:], authentication: auth,
            authenticationTransport: { _ in XCTFail("Mismatched origin cannot refresh"); throw HASessionError.originMismatch }, authenticationConnection: {})
        let image = await store.image("image.fixture")
        let snapshot = await store.snapshot("camera.fixture")
        XCTAssertNil(image)
        XCTAssertNil(snapshot)
        XCTAssertTrue(store.snapshots.isEmpty)
    }

    func testCancelledPictureRequestNeverReadsCredentialOrUsesTransport() async throws {
        let (defaults, domain) = try preferences()
        defer { defaults.removePersistentDomain(forName: domain) }
        let auth = HATokenSession(vault: .init(load: { XCTFail("Cancelled request cannot read credentials"); return nil },
            legacy: { XCTFail("No legacy read"); return nil }, save: { _ in XCTFail("No save") }, clear: {}))
        let store = HomeStore(defaults: defaults, environment: [:], authentication: auth,
            authenticationTransport: { _ in XCTFail("No network"); throw CancellationError() }, authenticationConnection: {})
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            return await store.pictureData(at: "https://other.example/api/camera_proxy/camera.fixture")
        }
        let data = await task.value
        XCTAssertNil(data)
        XCTAssertTrue(store.snapshots.isEmpty)
    }
}
