import XCTest
@testable import Hearth

@MainActor
final class ClimateModeConfirmationTests: XCTestCase {
    func testAlreadyPushedModeNeedsNoSnapshotOrDelay() async throws {
        let confirmed = try await ClimateModeConfirmation.wait(for: "auto", currentMode: { "auto" },
            refresh: { XCTFail("Already confirmed by a push") }, isCurrent: { true },
            pause: { XCTFail("Already confirmed by a push") })
        XCTAssertTrue(confirmed)
    }

    func testImmediateSnapshotConfirmsWithoutWaiting() async throws {
        var mode = "cool", reads = 0
        let confirmed = try await ClimateModeConfirmation.wait(for: "auto", currentMode: { mode },
            refresh: { reads += 1; mode = "auto" }, isCurrent: { true },
            pause: { XCTFail("Fresh confirmation must not wait five seconds") })
        XCTAssertTrue(confirmed)
        XCTAssertEqual(reads, 1)
    }

    func testLatePushFinishesAtFirstObservedConfirmation() async throws {
        var mode = "cool", reads = 0, pauses = 0
        let confirmed = try await ClimateModeConfirmation.wait(for: "dry", currentMode: { mode },
            refresh: { reads += 1 }, isCurrent: { true },
            pause: { pauses += 1; mode = "dry" })
        XCTAssertTrue(confirmed)
        XCTAssertEqual(reads, 1)
        XCTAssertEqual(pauses, 1)
    }

    func testMissingOrUnchangedSnapshotDoesNotInventSuccess() async throws {
        let reports: [String?] = [nil, "cool", "off"]
        for reported in reports {
            var reads = 0, pauses = 0
            let confirmed = try await ClimateModeConfirmation.wait(for: "fan_only", currentMode: { reported },
                refresh: { reads += 1 }, isCurrent: { true }, pause: { pauses += 1 })
            XCTAssertFalse(confirmed)
            XCTAssertEqual(reads, 2, "Immediate and final authoritative reads remain available")
            XCTAssertEqual(pauses, 20, "Retain the existing bounded event-wait budget")
        }
    }

    func testFinalSnapshotCanConfirmAfterEventWait() async throws {
        var mode = "cool", reads = 0, pauses = 0
        let confirmed = try await ClimateModeConfirmation.wait(for: "auto", currentMode: { mode },
            refresh: { reads += 1; if reads == 2 { mode = "auto" } }, isCurrent: { true },
            pause: { pauses += 1 })
        XCTAssertTrue(confirmed)
        XCTAssertEqual(reads, 2)
        XCTAssertEqual(pauses, 20)
    }

    func testStaleSessionDoesNotReadEvenIfModeMatches() async {
        do {
            _ = try await ClimateModeConfirmation.wait(for: "auto", currentMode: { "auto" },
                refresh: { XCTFail("Old session must not read") }, isCurrent: { false },
                pause: { XCTFail("Old session must not wait") })
            XCTFail("Old session must not claim confirmation")
        } catch { XCTAssertTrue(error is CancellationError) }
    }

    func testSessionChangeDuringSnapshotRejectsItsResult() async {
        var current = true, mode = "cool"
        do {
            _ = try await ClimateModeConfirmation.wait(for: "auto", currentMode: { mode },
                refresh: { current = false; mode = "auto" }, isCurrent: { current },
                pause: { XCTFail("Do not wait on the replacement session") })
            XCTFail("Old result must not be accepted")
        } catch { XCTAssertTrue(error is CancellationError) }
    }

    func testSessionChangeDuringEventWaitDoesNotRefreshNewSession() async {
        var current = true, reads = 0
        do {
            _ = try await ClimateModeConfirmation.wait(for: "auto", currentMode: { "cool" },
                refresh: { reads += 1 }, isCurrent: { current }, pause: { current = false })
            XCTFail("Old session must stop")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(reads, 1)
    }

    func testCancelledTaskDoesNotReadOrConfirm() async {
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await ClimateModeConfirmation.wait(for: "auto", currentMode: { "auto" },
                refresh: { XCTFail("Cancelled task must not read") }, isCurrent: { true },
                pause: { XCTFail("Cancelled task must not wait") })
        }
        do { _ = try await task.value; XCTFail("Cancellation must propagate") }
        catch { XCTAssertTrue(error is CancellationError) }
    }

    func testCancellationDuringRefreshRejectsNewMode() async {
        var mode = "cool"
        let task = Task { @MainActor in
            try await ClimateModeConfirmation.wait(for: "auto", currentMode: { mode },
                refresh: { mode = "auto"; withUnsafeCurrentTask { $0?.cancel() } },
                isCurrent: { true }, pause: { XCTFail("Cancelled task must not wait") })
        }
        do { _ = try await task.value; XCTFail("Cancellation must propagate") }
        catch { XCTAssertTrue(error is CancellationError) }
    }
}
