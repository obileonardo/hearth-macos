import Foundation
import XCTest
@testable import Hearth

@MainActor
final class ClimateModeRecoveryTests: XCTestCase {
    private func entity(_ state: String = "cool") -> Entity {
        Entity(id: "climate.fixture", state: state, attributes: ["hvac_modes": ["off", "cool", "auto", "dry", "fan_only"]])
    }
    private var rejected: Error { ProviderError("Validation error: Fail device control") }
    private var action: DeviceCommand { ClimateCommand.mode(entity(), requested: "auto")! }

    func testSuccessNeverRetriesOrRefreshes() async throws {
        var calls = 0
        try await ClimateModeRecovery.perform(action, initial: entity(), send: { _ in calls += 1 },
                                              refresh: { XCTFail("Success needs no recovery"); return nil },
                                              settle: { XCTFail("Success needs no delay") })
        XCTAssertEqual(calls, 1)
    }
    func testKnownRejectionRetriesSamePayloadOnceAfterSettle() async throws {
        var calls: [DeviceCommand] = [], settled = false, reads = 0
        let request = action
        try await ClimateModeRecovery.perform(request, initial: entity(), send: { value in
            calls.append(value)
            if calls.count == 1 { throw self.rejected }
            XCTAssertTrue(settled)
        }, refresh: { reads += 1; return self.entity() }, settle: { settled = true })
        XCTAssertEqual(calls.count, 2)
        XCTAssertEqual(calls[0].data["hvac_mode"] as? String, calls[1].data["hvac_mode"] as? String)
        XCTAssertEqual(calls[1].entityID, request.entityID)
        XCTAssertEqual(reads, 2)
    }
    func testAlreadyReportedModeAvoidsDuplicateRequest() async throws {
        var calls = 0
        try await ClimateModeRecovery.perform(action, initial: entity(), send: { _ in calls += 1; throw self.rejected },
                                              refresh: { self.entity("auto") }, settle: { XCTFail("Already applied") })
        XCTAssertEqual(calls, 1)
    }
    func testChangedDeviceStateIsNotOverridden() async {
        var calls = 0
        do {
            try await ClimateModeRecovery.perform(action, initial: entity(), send: { _ in calls += 1; throw self.rejected },
                                                  refresh: { self.entity("off") }, settle: { XCTFail("User changed power") })
            XCTFail("Changed state must preserve rejection")
        } catch { XCTAssertEqual(calls, 1) }
    }
    func testChangeDuringSettlePreventsRetry() async {
        var calls = 0, reads = 0
        do {
            try await ClimateModeRecovery.perform(action, initial: entity(), send: { _ in calls += 1; throw self.rejected },
                                                  refresh: { reads += 1; return self.entity(reads == 1 ? "cool" : "off") }, settle: {})
            XCTFail("Changed state must not be overwritten")
        } catch { XCTAssertEqual(calls, 1) }
    }
    func testUnrelatedFailureNeverRetries() async {
        var calls = 0
        do {
            try await ClimateModeRecovery.perform(action, initial: entity(), send: { _ in calls += 1; throw ProviderError("Not connected") },
                                                  refresh: { XCTFail("Unrelated failure"); return nil }, settle: {})
            XCTFail("Failure must propagate")
        } catch { XCTAssertEqual(calls, 1) }
    }
    func testSecondRejectionPropagatesWithoutLoop() async {
        var calls = 0
        do {
            try await ClimateModeRecovery.perform(action, initial: entity(), send: { _ in calls += 1; throw self.rejected },
                                                  refresh: { self.entity() }, settle: {})
            XCTFail("Second failure must propagate")
        } catch { XCTAssertEqual(calls, 2) }
    }
    func testUnavailableRefreshDoesNotResend() async {
        var calls = 0
        do {
            try await ClimateModeRecovery.perform(action, initial: entity(), send: { _ in calls += 1; throw self.rejected },
                                                  refresh: { nil }, settle: {})
            XCTFail("Missing state must prevent retry")
        } catch { XCTAssertEqual(calls, 1) }
    }
    func testAppliedWhileSettlingAvoidsSecondRequest() async throws {
        var calls = 0, reads = 0
        try await ClimateModeRecovery.perform(action, initial: entity(), send: { _ in calls += 1; throw self.rejected },
                                              refresh: { reads += 1; return self.entity(reads == 1 ? "cool" : "auto") }, settle: {})
        XCTAssertEqual(calls, 1)
    }
    func testCancelledSettleDoesNotSendAgain() async {
        var calls = 0
        do {
            try await ClimateModeRecovery.perform(action, initial: entity(), send: { _ in calls += 1; throw self.rejected },
                                                  refresh: { self.entity() }, settle: { throw CancellationError() })
            XCTFail("Cancelled recovery must stop")
        } catch { XCTAssertEqual(calls, 1); XCTAssertTrue(error is CancellationError) }
    }
    func testTemperatureCommandsNeverRetry() async {
        var calls = 0
        let temperature = DeviceCommand(domain: "climate", service: "set_temperature", entityID: entity().id, data: ["temperature": 24])
        do {
            try await ClimateModeRecovery.perform(temperature, initial: entity(), send: { _ in calls += 1; throw self.rejected },
                                                  refresh: { XCTFail("Only mode requests recover"); return nil }, settle: {})
            XCTFail("Failure must propagate")
        } catch { XCTAssertEqual(calls, 1) }
    }

}
