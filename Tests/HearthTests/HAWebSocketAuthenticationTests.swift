import XCTest
@testable import Hearth

final class HAWebSocketAuthenticationTests: XCTestCase {
    private let home = URL(string: "https://home.example")!
    func testSecureSocketAndHTTPHandshakeNormalizeToSameOrigin() {
        for value in ["wss://HOME.example:443/api/websocket", "https://home.example/api/websocket"] {
            XCTAssertTrue(HAWebSocketAuthentication.matches(URL(string: value)!, expected: home))
        }
    }
    func testSocketRedirectCannotChangeHostPortSchemeOrCredentials() {
        for value in ["wss://other.example/api/websocket", "ws://home.example/api/websocket", "wss://home.example:8123/api/websocket", "wss://u:p@home.example/api/websocket", "file:///socket"] {
            XCTAssertFalse(HAWebSocketAuthentication.matches(URL(string: value)!, expected: home))
        }
    }
    func testAuthenticationRequiresExpectedChallengeAndActualEndpoint() {
        let socket = URL(string: "wss://home.example/api/websocket")!
        XCTAssertTrue(HAWebSocketAuthentication.maySend(first: ["type": "auth_required"], currentRequest: socket, response: nil, expected: home))
        XCTAssertFalse(HAWebSocketAuthentication.maySend(first: ["type": "auth_ok"], currentRequest: socket, response: nil, expected: home))
        XCTAssertFalse(HAWebSocketAuthentication.maySend(first: ["type": "auth_required"], currentRequest: nil, response: nil, expected: home))
        XCTAssertFalse(HAWebSocketAuthentication.maySend(first: ["type": "auth_required"], currentRequest: socket, response: URL(string: "https://other.example"), expected: home))
    }
}
