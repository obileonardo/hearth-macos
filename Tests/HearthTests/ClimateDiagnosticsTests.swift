import Foundation
import XCTest
@testable import Hearth

final class ClimateDiagnosticsTests: XCTestCase {
    private var entity: Entity {
        Entity(id: "climate.fixture_private_room", state: "cool", attributes: [
            "friendly_name": "Private fixture room", "hvac_modes": ["cool", "auto", "custom_private_mode"],
            "temperature": 23.75, "current_temperature": 22.25,
            "min_temp": 16.0, "max_temp": 30.0, "target_temp_step": 0.25,
        ])
    }

    func testReportExcludesIdentifiersActualTemperaturesAndRawErrors() {
        let raw = "Vendor refused https://example.invalid/private with secret_fixture_value"
        let report = ClimateDiagnostics.report(initial: entity, reported: entity, requestedMode: "auto",
                                               outcome: .rejected, error: ProviderError(raw))
        for excluded in [entity.id, "Private fixture room", "custom_private_mode", "23.75", "22.25", "example.invalid", "secret_fixture_value", raw] {
            XCTAssertFalse(report.contains(excluded), "Report leaked an unallowlisted value")
        }
        XCTAssertTrue(report.contains("Requested mode: auto"))
        XCTAssertTrue(report.contains("Error category: provider error"))
        XCTAssertTrue(report.contains("Temperature step: 0.25"))
        XCTAssertTrue(report.contains("Other advertised modes: 1"))
    }

    func testUnknownModesNeverLeakCustomText() {
        var unknown = entity
        unknown.state = "private_custom_state"
        let report = ClimateDiagnostics.report(initial: unknown, reported: unknown, requestedMode: "private_requested_mode", outcome: .unconfirmed)
        XCTAssertFalse(report.contains("private_custom_state"))
        XCTAssertFalse(report.contains("private_requested_mode"))
        XCTAssertTrue(report.contains("Requested mode: other"))
        XCTAssertTrue(report.contains("Reported mode: other"))
    }

    func testKnownRejectionAndNetworkErrorsUseFixedCategories() {
        let rejected = ClimateDiagnostics.report(initial: entity, reported: nil, requestedMode: "dry", outcome: .rejected,
                                                 error: ProviderError("Validation error: Fail device control"))
        XCTAssertTrue(rejected.contains("Error category: vendor rejected device control"))
        XCTAssertTrue(rejected.contains("Reported mode: not available"))
        let timedOut = ClimateDiagnostics.report(initial: entity, reported: nil, outcome: .rejected, error: URLError(.timedOut))
        XCTAssertTrue(timedOut.contains("Error category: network timeout"))
        XCTAssertTrue(timedOut.contains("Action: set_temperature"))
    }
}
