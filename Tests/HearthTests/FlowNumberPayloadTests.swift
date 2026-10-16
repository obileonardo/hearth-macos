import XCTest
@testable import Hearth

final class FlowNumberPayloadTests: XCTestCase {
    func testOrdinaryWholeAndFractionalNumbersKeepTheirTypes() throws {
        XCTAssertEqual(try FlowNumberPayload.value("24", step: 1) as? Int, 24)
        XCTAssertEqual(try FlowNumberPayload.value("24.25", step: 0.25) as? Double, 24.25)
        XCTAssertEqual(try FlowNumberPayload.value("24,5", step: 0.5) as? Double, 24.5)
        XCTAssertEqual(try FlowNumberPayload.value(24.0, step: nil) as? Double, 24)
    }

    func testNonfiniteInputsAreRejectedBeforeJSONSubmission() {
        for value in [Double.nan, .infinity, -.infinity] {
            XCTAssertThrowsError(try FlowNumberPayload.value(value, step: 1))
        }
        for value in ["nan", "inf", "-inf"] {
            XCTAssertThrowsError(try FlowNumberPayload.value(value, step: 1))
        }
    }

    func testFiniteValuesOutsideIntegerRangeRemainJSONSafeDoubles() throws {
        for value in [Double(Int.max), Double.greatestFiniteMagnitude, -Double.greatestFiniteMagnitude] {
            let result = try XCTUnwrap(FlowNumberPayload.value(value, step: 1))
            XCTAssertEqual(result as? Double, value)
            XCTAssertTrue(JSONSerialization.isValidJSONObject(["value": result]))
        }
    }

    func testUnparseableOptionalInputKeepsExistingOmissionBehavior() throws {
        XCTAssertNil(try FlowNumberPayload.value("", step: 1))
        XCTAssertNil(try FlowNumberPayload.value("not a number", step: 1))
    }
}

final class HAAdminGuideSnapshotTests: XCTestCase {
    @MainActor func testFixtureHasOnlyExplicitGenericIdentityAndServer() {
        let sample = HAAdminGuideSnapshot.example()
        XCTAssertEqual(sample.user.id, "preview-user")
        XCTAssertEqual(sample.user.username, "demo")
        XCTAssertEqual(sample.server.internalURL, "http://homeassistant.local:8123")
        XCTAssertNil(sample.server.externalURL)
        XCTAssertTrue(sample.entries.allSatisfy { $0.id.hasPrefix("preview-") })
    }

    @MainActor func testHomeKitExamplesKeepImportAndExportIntegrationsDistinct() {
        let sample = HAAdminGuideSnapshot.example(section: .add)
        XCTAssertEqual(sample.section, .add)
        XCTAssertEqual(sample.name(of: "homekit_controller"), "HomeKit Device")
        XCTAssertEqual(sample.name(of: "homekit"), "HomeKit Bridge")
    }
}
