import Foundation
import XCTest
@testable import Hearth

final class HAOriginTests: XCTestCase {
    func testOriginNormalizationAndBoundaries() throws {
        let base = try XCTUnwrap(URL(string: "https://home.example"))
        for same in ["https://HOME.example:443/image", "https://home.example/api/image?x=1"] {
            XCTAssertTrue(HAOrigin.matches(try XCTUnwrap(URL(string: same)), base))
        }
        for other in ["http://home.example", "https://home.example:8123", "https://home.example.evil.test",
                      "https://other.example", "https://user:pass@home.example", "file:///image"] {
            XCTAssertFalse(HAOrigin.matches(try XCTUnwrap(URL(string: other)), base))
        }
    }

    func testRedirectCredentialsStayAtHomeOrigin() throws {
        let origin = try XCTUnwrap(URL(string: "http://home.example:8123"))
        var same = URLRequest(url: try XCTUnwrap(URL(string: "http://home.example:8123/image")))
        same.setValue("Bearer fixture-session", forHTTPHeaderField: "Authorization")
        same.setValue("fixture=yes", forHTTPHeaderField: "Cookie")
        XCTAssertEqual(HAOrigin.sanitizedRedirect(same, origin: origin)?.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-session")
        var external = same
        external.url = URL(string: "https://art.example/image")
        let result = try XCTUnwrap(HAOrigin.sanitizedRedirect(external, origin: origin))
        XCTAssertNil(result.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(result.value(forHTTPHeaderField: "Cookie"))
        external.url = URL(string: "file:///image")
        XCTAssertNil(HAOrigin.sanitizedRedirect(external, origin: origin))
        external.url = URL(string: "https://user:pass@art.example/image")
        XCTAssertNil(HAOrigin.sanitizedRedirect(external, origin: origin))
    }

    func testBrowserGuardEscapesAndRestrictsOrigin() throws {
        XCTAssertEqual(HAOrigin.javaScriptGuard(for: try XCTUnwrap(URL(string: "https://home.example:443/path"))),
                       "window.location.origin === \"https:\\/\\/home.example\"")
        let ipv6 = try XCTUnwrap(HAOrigin.javaScriptGuard(for: try XCTUnwrap(URL(string: "http://[::1]:8123"))))
        XCTAssertTrue(ipv6.contains("[::1]:8123"))
        XCTAssertNil(HAOrigin.javaScriptGuard(for: try XCTUnwrap(URL(string: "https://u:p@home.example"))))
        XCTAssertNil(HAOrigin.javaScriptGuard(for: try XCTUnwrap(URL(string: "file:///tmp/page"))))
    }
}
